-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE POKéBLOCK CASE: forty slots, and the only way a Pokémon's condition
-- ever moves.
--
-- Each row is a colour, its five flavour values and its FEEL -- and feel is
-- the one number that matters most, because it is spent out of a budget of
-- 255 that never refills.  The case shows `min(feel, 99)`, which is a display
-- clamp and not the price: a block that says 99 can really cost 108.
--
-- USE feeds it to a Pokémon.  The stat that moves is the flavour's, by the
-- flavour's own value, and exactly ONE of the five is adjusted by a tenth --
-- up if the Pokémon's nature likes that flavour, down if it dislikes it, and
-- not at all for a neutral nature.

local Contest = require("src.pokemon.Contest")
local Font = require("src.render.Font")
local Pokeblocks = require("src.inventory.Pokeblocks")
local Screens = require("src.ui.Screens")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3PokeblockCase = {}
Gen3PokeblockCase.__index = Gen3PokeblockCase
Gen3PokeblockCase.isOpaque = true

local GBA_W, GBA_H = 240, 160
local ROWS = 7

-- ---------------------------------------------------------------------------
-- THE CARTRIDGE'S OWN WORDS
--
-- Reported from play: "make sure the berry crusher and pokeblock maker menus
-- work properly."  The case was printing this port's English -- "Threw away
-- the POKéBLOCK." -- because nothing had read the cartridge's, which sits in
-- one run right behind the fourteen block names and is now extracted
-- (constants.gen3Pokeblocks.text).  The three actions are the bag's own USE,
-- TOSS and CANCEL, which the import already reads.
--
-- A dataset without either falls back to the port's own English rather than
-- printing nothing.
local function words(game)
  local r = (game and game.data and game.data.constants or {}).gen3Pokeblocks
  return (r and r.text) or {}
end

local function bagWord(game, index, fallback)
  local screens = (game and game.data and game.data.constants or {}).gen3Screens
  local items = screens and screens.bagActions and screens.bagActions.items
  local word = items and items[index]
  return (type(word) == "string" and word ~= "") and word or fallback
end

-- {STR_VAR_1} / {STR_VAR_2}, filled the way every other Gen 3 screen fills
-- them: the extractor writes them as {VAR1} and {VAR2}.
local function fill(text, vars)
  if type(text) ~= "string" then return nil end
  return (text:gsub("{VAR(%d)}", function(n)
    return tostring(vars[tonumber(n)] or "")
  end))
end

-- The bag's action list: USE is 1, TOSS is 2 and CANCEL is 8.
local ACTION_USE, ACTION_TOSS, ACTION_CANCEL = 1, 2, 8

function Gen3PokeblockCase:uiSize() return GBA_W, GBA_H end
function Gen3PokeblockCase:wantsFillScale() return true end

function Gen3PokeblockCase.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen3PokeblockCase)
  self.game = game
  self.onDone = opts.onDone
  self.onCancel = opts.onCancel
  -- opened to CHOOSE one (the Contest Lady, a feeder) rather than to use it
  self.pickOnly = opts.pickOnly
  self.onPick = opts.onPick
  self.index = 1
  self.top = 1
  self.message = nil
  self:rebuild()
  return self
end

function Gen3PokeblockCase:rebuild()
  local case = Pokeblocks.case(self.game.save)
  local rows = {}
  for slot = 1, Pokeblocks.caseSize(self.game.data) do
    local block = case[slot]
    if block then rows[#rows + 1] = { slot = slot, block = block } end
  end
  -- ...and the way out, which the cartridge puts at the bottom of the list
  -- rather than leaving B as the only exit
  rows[#rows + 1] = { close = true,
                      label = words(self.game).stow or Strings("Stow CASE.") }
  self.rows = rows
  self.index = math.max(1, math.min(self.index, #rows))
  self.top = math.max(1, math.min(self.top or 1,
                                  math.max(1, #rows - ROWS + 1)))
end

function Gen3PokeblockCase:close()
  if self.game.stack then self.game.stack:pop() end
  if self.onCancel then self.onCancel() end
  if self.onDone then self.onDone() end
end

-- A ROW WAS CHOSEN.  Picking (the Contest Lady, the Safari feeder) takes the
-- block straight away; otherwise the cartridge asks USE, TOSS or CANCEL
-- first, which is the menu this screen never had.
function Gen3PokeblockCase:choose()
  local row = self.rows[self.index]
  if not row or row.close then return self:close() end
  if self.pickOnly then
    if self.game.stack then self.game.stack:pop() end
    if self.onPick then self.onPick(row.slot, row.block) end
    if self.onDone then self.onDone() end
    return
  end
  local game = self.game
  local Menu = require("src.ui.Menu")
  local menu = Menu.new(game, {
    { label = bagWord(game, ACTION_USE, Strings("USE")),
      onSelect = function() self:use(row) end },
    { label = bagWord(game, ACTION_TOSS, Strings("TOSS")),
      onSelect = function() self:toss(row) end },
    { label = bagWord(game, ACTION_CANCEL, Strings("CANCEL")),
      onSelect = function() end },
  }, { tx = 20, ty = 11, tw = 9, th = 7 })
  game.stack:push(menu)
end

function Gen3PokeblockCase:use(row)
  row = row or self.rows[self.index]
  if not (row and row.block) then return end
  local game = self.game
  local pushed = pcall(Screens.push, game, "PartyMenu", {
    pickOnly = true,
    onCancel = function() end,
    onSwitch = function(mon)
      local deltas = Pokeblocks.feed(game.data, mon, row.block)
      if not deltas then
        -- SHEEN IS A HARD GATE, not a taper: a Pokémon at 255 refuses the
        -- block outright and nothing at all changes, the block included.
        self.message = Strings("It won't eat any more.")
        return
      end
      local name = Pokeblocks.name(game.data, row.block)
      Pokeblocks.remove(game.save, row.slot)
      self:rebuild()
      -- THE CARTRIDGE HAS THREE LINES FOR THIS, one per reaction, and each
      -- is a whole sentence rather than a verb to slot into one.
      local w = words(game)
      local line = ((deltas.liked or 0) > 0 and w.ateHappily)
                   or ((deltas.liked or 0) < 0 and w.ateDisdainfully)
                   or w.ate
      local who = mon.nickname or tostring(mon.species)
      self.message = fill(line, { who, name })
                     or Strings("%s ate the %s.", who, name)
    end,
  })
  if not pushed then self.message = Strings("Nothing happened.") end
end

-- TOSSING ASKS FIRST.  Forty slots and no way back is exactly the case where
-- a stray A press costs a block that took a whole blend to make.
function Gen3PokeblockCase:toss(row)
  row = row or self.rows[self.index]
  if not (row and row.block) then return end
  local game = self.game
  local w = words(game)
  local name = Pokeblocks.name(game.data, row.block)
  local TextBox = require("src.render.TextBox")
  local ask = fill(w.tossAsk, { name })
              or Strings("Throw away this\n%s?", name)
  game.stack:push(TextBox.new(game, ask, nil, {
    choice = function(yes)
      if not yes then return end
      Pokeblocks.remove(game.save, row.slot)
      self:rebuild()
      self.message = fill(w.tossed, { name })
                     or Strings("The %s\nwas thrown away.", name)
    end,
  }))
end

function Gen3PokeblockCase:update()
  local input = self.game.input
  if not input then return end
  if self.message then
    if input:wasPressed("a") or input:wasPressed("b") then
      Sound.play(self.game.data, "Press_AB")
      self.message = nil
    end
    return
  end
  if input:wasPressed("b") then
    Sound.play(self.game.data, "Press_AB")
    return self:close()
  end
  if input:wasPressed("down") then
    self.index = self.index % math.max(1, #self.rows) + 1
    if self.index > self.top + ROWS - 1 then self.top = self.index - ROWS + 1 end
    Sound.play(self.game.data, "Press_AB")
  elseif input:wasPressed("up") then
    self.index = (self.index - 2) % math.max(1, #self.rows) + 1
    if self.index < self.top then self.top = self.index end
    Sound.play(self.game.data, "Press_AB")
  elseif input:wasPressed("a") then
    Sound.play(self.game.data, "Press_AB")
    self:choose()
  end
end

function Gen3PokeblockCase:keypressed(key)
  if key == "b" then return self:close() end
end

function Gen3PokeblockCase:draw()
  local game = self.game
  love.graphics.setColor(0.24, 0.30, 0.20, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 0, 30, 15)
  Font.drawBox(0, 15, 30, 5)
  love.graphics.setColor(0, 0, 0, 1)

  local w = words(game)
  for i = 0, ROWS - 1 do
    local row = self.rows[self.top + i]
    if not row then break end
    local y = 12 + i * 16
    if row.close then
      Font.draw(row.label, 20, y)
    else
      Font.draw(Pokeblocks.name(game.data, row.block), 20, y)
      local feel = tostring(Pokeblocks.shownFeel(row.block))
      Font.draw(feel, 220 - Font.width(feel), y)
    end
    if self.top + i == self.index then Font.drawCode(Theme.cursor, 8, y) end
  end

  local row = self.rows[self.index]
  if row and row.block then
    local b = row.block
    -- SPICY DRY SWEET BITTER SOUR, in the cartridge's own words and its own
    -- order; a dataset without them keeps the two-letter shorthand
    local labels = w.flavours
    local parts = {}
    for n, key in ipairs(Pokeblocks.FLAVOURS) do
      local label = (labels and labels[n]) or key:sub(1, 2):upper()
      parts[#parts + 1] = ("%s %d"):format(label,
                                           math.floor(tonumber(b[key]) or 0))
    end
    Font.draw(table.concat(parts, " "), 8, 124)
    Font.draw(("%s %d"):format(w.feel or Strings("FEEL"),
                               Pokeblocks.shownFeel(b)), 8, 140)
  end

  if self.message then
    love.graphics.setColor(1, 1, 1, 1)
    Font.drawBox(0, 15, 30, 5)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(self.message, 8, 128)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3PokeblockCase
