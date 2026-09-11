-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Emerald's Pokedex SEARCH -- the screen behind START and SELECT.
--
-- Reported from play: "for the pokedex in emerald the start and select
-- buttons arent working for search and menu like they do in the actual
-- rom/game".  The list screen has been DRAWING both hints for a while -- the
-- ripped sheet carries a SELECT plate beside the word SEARCH and a START
-- plate beside MENU, and Gen3Pokedex blits all four -- and neither key did
-- anything.  That is the worst of the two failures: the screen tells the
-- player the button is there, and the button is not.
--
-- WHAT THE TWO KEYS OPEN, which is one screen and not two.  START opens the
-- top bar (SEARCH / SWITCH DEX / CANCEL); SELECT skips it and drops straight
-- into the form the first of those rows opens.  So this file is one screen
-- with two panes and the key that opened it decides which pane you land on.
--
-- WHAT COMES OFF THE CARTRIDGE (constants.gen3PokedexMenu, derived by
-- RomExtractorGen3:extractPokedexMenu):
--   * the top bar's three rows, their tile columns and their SENTENCES --
--     "Search for POKeMON based on selected parameters.", "Switch POKeDEX
--     listings.", "Return to the POKeDEX.";
--   * the form's seven rows, their two boxes apiece and their sentences,
--     including the pair that share a line because the two type slots are
--     one question asked twice;
--   * every word the form can offer -- two dex modes, six listing modes,
--     nine letter groups, ten body colours -- and, for the modes, the
--     sentence each one explains itself with.
--
-- WHAT IS NOT ON THE CARTRIDGE AS TEXT.  The short labels down the left of
-- the form (NAME, COLOR, TYPE, ORDER, MODE) and the three words along the top
-- bar are drawn from the search screen's BACKGROUND, not printed, so they are
-- tiles this port has not ripped.  They are this file's own words, in this
-- port's own frames; everything a sentence, a column or an option says is the
-- cartridge's.
--
-- THE RESTRICTIONS ARE IN THE SENTENCES and are not invented here.  "Spotted
-- POKeMON only." is the name and colour searches; "Owned POKeMON only." is
-- the type search and the four size orders.  A TO Z is spotted; NUMERICAL is
-- neither.  Each row below reads its own sentence to decide.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3DexSearch = {}
Gen3DexSearch.__index = Gen3DexSearch
Gen3DexSearch.isOpaque = true

local GBA_W, GBA_H = 240, 160

-- The description window, which is the space the cartridge's own tables leave
-- under the form: the last row's title box is on line 12 and the screen is
-- twenty tiles tall.
local NOTE = { tx = 0, ty = 14, tw = 30, th = 6 }

-- RECONSTRUCTED, because the two tables give columns and lines and not
-- pixels: a row of the form is one line of text inside its box.
local PAD_X, PAD_Y = 4, 4
local VALUE_ROWS = 5      -- how much of an open option list is on screen

-- The port's own labels for the columns the cartridge draws as background.
local LABELS = { "NAME", "COLOR", "TYPE", "TYPE", "ORDER", "MODE" }
local TOPBAR = { "SEARCH", "SWITCH DEX", "CANCEL" }
-- ...and the word on the last row, which is the only one that changes with
-- which top-bar row opened the form.
local RUN = { search = "SEARCH", switch = "SWITCH" }

-- Which rows each pane offers.  SWITCH DEX asks only the two questions that
-- change the LISTING; SEARCH asks all of them.
local SEARCH_ROWS = { 1, 2, 3, 4, 5, 6, 7 }
local SWITCH_ROWS = { 5, 6, 7 }

function Gen3DexSearch:uiSize() return GBA_W, GBA_H end
function Gen3DexSearch:wantsFillScale() return true end

function Gen3DexSearch:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

-- Is this dataset carrying the derivation at all?  Without it there is no
-- screen to open, and the caller keeps the key inert rather than opening an
-- empty frame.
function Gen3DexSearch.available(game)
  local record = ((game and game.data or {}).constants or {}).gen3PokedexMenu
  return type(record) == "table"
     and type(record.topBar) == "table" and #record.topBar >= 3
     and type(record.items) == "table" and #record.items >= 7
     and type(record.orders) == "table" and #record.orders >= 1
end

-- ---------------------------------------------------------------------------
-- THE OPTIONS EACH ROW OFFERS.
--
-- The first four are lists with an "any" at the top -- the cartridge's own
-- DON'T SPECIFY. for a letter or a colour and its NONE for a type -- and the
-- last two are the mode lists, which have no "any" because the dex is always
-- in one of them.
-- ---------------------------------------------------------------------------

local ANY_TEXT = "DON’T SPECIFY."
local NONE_TEXT = "NONE"

function Gen3DexSearch:options(row)
  local R = self.record
  if row == 1 then
    local out = { { label = self.anyWord, value = nil } }
    for _, group in ipairs(R.letters or {}) do
      out[#out + 1] = { label = group, value = group }
    end
    return out
  elseif row == 2 then
    local out = { { label = self.anyWord, value = nil } }
    for i, colour in ipairs(R.colours or {}) do
      out[#out + 1] = { label = colour, value = i - 1 }
    end
    return out
  elseif row == 3 or row == 4 then
    local out = { { label = self.noneWord, value = nil } }
    local constants = self.game.data.constants or {}
    for _, id in ipairs(constants.typeOrder or {}) do
      local def = (constants.types or {})[id]
      -- MYSTERY is the cartridge's filler between the physical types and the
      -- special ones and is not offered as a search
      if def and def.name and def.name ~= "???" then
        out[#out + 1] = { label = def.name, value = id }
      end
    end
    return out
  elseif row == 5 then
    local out = {}
    for i, mode in ipairs(R.orders or {}) do
      out[#out + 1] = { label = mode.name, value = i,
                        description = mode.description }
    end
    return out
  elseif row == 6 then
    local out = {}
    for i, mode in ipairs(R.dexModes or {}) do
      out[#out + 1] = { label = mode.name, value = i,
                        description = mode.description }
    end
    return out
  end
  return {}
end

function Gen3DexSearch.new(game, opts)
  opts = opts or {}
  local self = setmetatable({ game = game, opts = opts }, Gen3DexSearch)
  self.record = ((game.data or {}).constants or {}).gen3PokedexMenu or {}
  local R = self.record
  -- the cartridge's own two "no answer" words, kept where the derivation put
  -- them and falling back to the port's if a dataset predates the stage
  self.anyWord = tostring(R.anyText or ANY_TEXT)
  self.noneWord = tostring(R.noneText or NONE_TEXT)

  -- WHICH PANE.  `opts.pane` is "topbar" for START and "form" for SELECT;
  -- SELECT lands on the SEARCH form, which is the row it would have picked.
  self.pane = (opts.pane == "form") and "form" or "topbar"
  self.mode = "search"
  self.bar = 1
  self.row = 1
  self.picking = nil

  -- the answers, which start where the dex already is
  self.choice = { nil, nil, nil, nil, 1, 1 }
  if type(opts.mode) == "number" then self.choice[6] = opts.mode end
  if type(opts.order) == "number" then self.choice[5] = opts.order end
  return self
end

-- The rows this pane offers, in order.
function Gen3DexSearch:rows()
  return (self.mode == "switch") and SWITCH_ROWS or SEARCH_ROWS
end

function Gen3DexSearch:rowAt(slot)
  local rows = self:rows()
  return rows[slot]
end

function Gen3DexSearch:slotOf(row)
  for i, r in ipairs(self:rows()) do if r == row then return i end end
  return 1
end

-- The MODE row is only a question once the national dex exists; before that
-- the cartridge has one mode and does not ask.
function Gen3DexSearch:offers(row)
  if row ~= 6 then return true end
  local national = self.game.save and self.game.save.nationalDex
  return national and #(self.record.dexModes or {}) >= 2
end

function Gen3DexSearch:beep()
  Sound.play(self.game.data, "Press_AB")
end

-- ---------------------------------------------------------------------------
-- INPUT
-- ---------------------------------------------------------------------------

function Gen3DexSearch:update()
  local input = self.game.input
  if self.picking then return self:updatePicking(input) end
  if self.pane == "topbar" then return self:updateTopBar(input) end
  return self:updateForm(input)
end

function Gen3DexSearch:close(result)
  self.game.stack:pop()
  if self.opts.onDone then self.opts.onDone(result) end
end

function Gen3DexSearch:updateTopBar(input)
  if input:wasPressed("b") then
    self:beep()
    return self:close(nil)
  end
  local bar = self.bar
  if input:wasPressed("left") then bar = bar - 1
  elseif input:wasPressed("right") then bar = bar + 1 end
  local most = #(self.record.topBar or {})
  if bar < 1 then bar = 1 elseif bar > most then bar = most end
  if bar ~= self.bar then
    self.bar = bar
    self:beep()
  end
  if input:wasPressed("a") then
    self:beep()
    if self.bar == 3 then return self:close(nil) end
    self.mode = (self.bar == 2) and "switch" or "search"
    self.pane = "form"
    self.row = self:rowAt(1)
  end
end

function Gen3DexSearch:updateForm(input)
  if input:wasPressed("b") then
    self:beep()
    -- SELECT came straight here, so B leaves the dex search entirely; START
    -- came through the bar, so B goes back to it
    if self.opts.pane == "form" then return self:close(nil) end
    self.pane = "topbar"
    return
  end
  local slot = self:slotOf(self.row)
  if input:wasPressed("up") then slot = slot - 1
  elseif input:wasPressed("down") then slot = slot + 1 end
  local rows = self:rows()
  if slot < 1 then slot = #rows elseif slot > #rows then slot = 1 end
  -- ...stepping over a row this dataset does not ask
  local guard = 0
  while not self:offers(rows[slot]) and guard < #rows do
    slot = slot + 1
    if slot > #rows then slot = 1 end
    guard = guard + 1
  end
  if rows[slot] ~= self.row then
    self.row = rows[slot]
    self:beep()
  end

  -- LEFT and RIGHT on the type pair move between the two slots, which is the
  -- one place in the form where two rows share a line.
  if self.row == 3 and input:wasPressed("right") then
    self.row = 4
    self:beep()
  elseif self.row == 4 and input:wasPressed("left") then
    self.row = 3
    self:beep()
  end

  if input:wasPressed("a") then
    self:beep()
    if self.row == 7 then return self:run() end
    self.list = self:options(self.row)
    if #self.list == 0 then return end
    self.picking = self.row
    self.pick = 1
    for i, option in ipairs(self.list) do
      if option.value == self.choice[self.row] then self.pick = i break end
    end
    self.pickTop = math.max(0, math.min(self.pick - 1,
                                        #self.list - VALUE_ROWS))
  end
end

function Gen3DexSearch:updatePicking(input)
  if input:wasPressed("b") then
    self:beep()
    self.picking, self.list = nil, nil
    return
  end
  local pick = self.pick
  if input:wasPressed("up") then pick = pick - 1
  elseif input:wasPressed("down") then pick = pick + 1 end
  if pick < 1 then pick = #self.list elseif pick > #self.list then pick = 1 end
  if pick ~= self.pick then
    self.pick = pick
    self:beep()
    local top = self.pickTop or 0
    if pick - 1 < top then top = pick - 1 end
    if pick > top + VALUE_ROWS then top = pick - VALUE_ROWS end
    self.pickTop = math.max(0, math.min(top, #self.list - VALUE_ROWS))
  end
  if input:wasPressed("a") then
    self:beep()
    self.choice[self.picking] = self.list[self.pick].value
    self.picking, self.list = nil, nil
  end
end

-- ---------------------------------------------------------------------------
-- WHAT THE LAST ROW DOES.
--
-- SWITCH hands back only the listing, which is what SWITCH DEX asked for.
-- SEARCH hands back the filter with it.  Neither one does the filtering: the
-- dex owns its own list, and this screen answers the question it was opened
-- to ask.
-- ---------------------------------------------------------------------------
function Gen3DexSearch:run()
  local out = {
    mode = self.choice[6],
    order = self.choice[5],
    switch = (self.mode == "switch") or nil,
  }
  if self.mode ~= "switch" then
    out.letter = self.choice[1]
    out.colour = self.choice[2]
    out.type1 = self.choice[3]
    out.type2 = self.choice[4]
  end
  self:close(out)
end

-- ---------------------------------------------------------------------------
-- DRAWING
-- ---------------------------------------------------------------------------

-- What the highlighted thing says about itself.  A row's sentence is the
-- cartridge's; an option list shows the option's own where it has one (the
-- two mode lists do), and the row's otherwise.
function Gen3DexSearch:sentence()
  local R = self.record
  if self.picking then
    local option = (self.list or {})[self.pick]
    if option and option.description then return option.description end
    local item = (R.items or {})[self.picking]
    return item and item.description or ""
  end
  if self.pane == "topbar" then
    local row = (R.topBar or {})[self.bar]
    return row and row.description or ""
  end
  local item = (R.items or {})[self.row]
  return item and item.description or ""
end

function Gen3DexSearch:valueLabel(row)
  local value = self.choice[row]
  if row == 1 then return value or self.anyWord end
  if row == 2 then
    local colours = self.record.colours or {}
    return value and colours[value + 1] or self.anyWord
  end
  if row == 3 or row == 4 then
    if not value then return self.noneWord end
    local def = ((self.game.data.constants or {}).types or {})[value]
    return def and def.name or tostring(value)
  end
  if row == 5 then
    local mode = (self.record.orders or {})[value or 1]
    return mode and mode.name or ""
  end
  if row == 6 then
    local mode = (self.record.dexModes or {})[value or 1]
    return mode and mode.name or ""
  end
  return ""
end

function Gen3DexSearch:draw()
  local R = self.record
  love.graphics.setColor(0.16, 0.24, 0.40, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  love.graphics.setColor(1, 1, 1, 1)

  -- ---- the top bar --------------------------------------------------------
  for i, row in ipairs(R.topBar or {}) do
    local tx, ty, tw = row.x, row.y, row.width
    Font.drawBox(tx, ty, tw, 2)
    local word = Strings(TOPBAR[i] or "")
    Font.draw(word, tx * 8 + PAD_X + 6, ty * 8 + PAD_Y)
    if self.pane == "topbar" and not self.picking and i == self.bar then
      Font.drawCode(Theme.cursor, tx * 8 + PAD_X - 2, ty * 8 + PAD_Y)
    end
  end

  -- ---- the form -----------------------------------------------------------
  for _, row in ipairs(self:rows()) do
    local item = (R.items or {})[row]
    if item and self:offers(row) then
      local t, s = item.title, item.selection
      Font.drawBox(t.x, t.y, t.width, 2)
      Font.draw(Strings(row == 7 and (RUN[self.mode] or "SEARCH")
                                 or (LABELS[row] or "")),
                t.x * 8 + PAD_X, t.y * 8 + PAD_Y)
      if s.width > 0 then
        Font.drawBox(s.x, s.y, s.width, 2)
        Font.draw(self:valueLabel(row), s.x * 8 + PAD_X, s.y * 8 + PAD_Y)
      end
      if self.pane == "form" and not self.picking and row == self.row then
        Font.drawCode(Theme.cursor, t.x * 8 + PAD_X - 4, t.y * 8 + PAD_Y)
      end
    end
  end

  -- ---- an open option list, which sits over the row it belongs to ---------
  if self.picking then
    local item = (R.items or {})[self.picking]
    local s = item and item.selection
    if s then
      local shown = math.min(VALUE_ROWS, #self.list)
      local h = shown * 2 + 2
      local ty = math.min(s.y, 20 - h)
      Font.drawBox(s.x, ty, math.max(s.width, 8), h)
      for i = 1, shown do
        local option = self.list[(self.pickTop or 0) + i]
        if option then
          local y = (ty + 1) * 8 + (i - 1) * 16 + PAD_Y - 4
          Font.draw(option.label, s.x * 8 + PAD_X + 6, y)
          if (self.pickTop or 0) + i == self.pick then
            Font.drawCode(Theme.cursor, s.x * 8 + PAD_X - 2, y)
          end
        end
      end
    end
  end

  -- ---- and the sentence the highlighted thing carries ---------------------
  Font.drawBox(NOTE.tx, NOTE.ty, NOTE.tw, NOTE.th)
  local y = (NOTE.ty + 1) * 8 + 2
  for line in (tostring(self:sentence()) .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" then
      Font.draw(line, (NOTE.tx + 1) * 8, y)
      y = y + Font.glyphHeight() + 2
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3DexSearch
