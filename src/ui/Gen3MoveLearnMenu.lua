-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- LEARNING A MOVE OVER A FULL SET, in Emerald's words on Emerald's screen.
--
-- Reported from play: "the move teaching screen is also falling back to the
-- gen1 move teaching screen".  The party half was fixed long ago -- picking
-- WHICH Pokemon learns the move opens Hoenn's party menu -- and what was left
-- was the screen after it, which was pokered's end to end: its lines, its
-- line breaks, and a 16x7 box at (4,5) laid out for a 160x144 screen.
--
-- Every line here is the cartridge's, read by
-- RomExtractorGen3:extractMoveLearnText out of the one contiguous run at
-- 05E9AA5 -- {VAR1} is the Pokemon and {VAR2} the move.  Two of them are not
-- translations of Gen 1's: this cartridge says "Stop trying to teach {move}?"
-- where pokered says "Abandon learning", and it names the MOVE where pokered
-- names the Pokemon.
--
-- WHERE THE QUESTION IS ASKED.  Emerald picks the move to forget on the
-- SUMMARY screen's moves page rather than in a box of its own: the page opens
-- with a cursor and the move being taught sits under the four as the thing
-- you pick to refuse it.  That is what this screen asks for now
-- (Gen3SummaryMenu's `choose`).  The list further down is the fallback for a
-- dataset whose summary screen will not open, and it says so rather than
-- pretending to be the cartridge's furniture.

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")

local Gen3MoveLearnMenu = {}
Gen3MoveLearnMenu.__index = Gen3MoveLearnMenu

-- ...on Hoenn's screen, not the Game Boy's.  Without this the surface is
-- 160x144 and a 240-wide layout is scaled up to fill it, which puts
-- everything right of about tile 20 off the edge -- the same fault the
-- Pokedex entry page had.
function Gen3MoveLearnMenu:uiSize()
  return require("src.ui.Theme").uiSize()
end

-- The lines, from the dataset where it has them.  A cache imported before
-- extractMoveLearnText existed keeps the same eight under the same names, so
-- the screen is never wordless.
local FALLBACK = {
  tryingToLearn = "{VAR1} wants to learn the\nmove {VAR2}.\fHowever, {VAR1} already\n"
                  .. "knows four moves.\fShould a move be deleted and\n"
                  .. "replaced with {VAR2}?",
  stopTeaching = "Stop trying to teach\n{VAR2}?",
  didNotLearn = "{VAR1} did not learn the\nmove {VAR2}.",
  whichForget = "Which move should be forgotten?",
  forgot = "1, 2, and… … … Poof!\f{VAR1} forgot how to\nuse {VAR2}.\fAnd…",
  learned = "{VAR1} learned\n{VAR2}!",
}

function Gen3MoveLearnMenu.line(game, role)
  local c = game and game.data and game.data.constants
  local r = c and c.gen3MoveLearn
  local line = (type(r) == "table" and r[role]) or FALLBACK[role]
  return line or ""
end

-- {VAR1} is the Pokemon, {VAR2} the move.  gsub's replacement is escaped
-- because a nickname may hold a percent sign.
local function fill(line, mon, move)
  local function safe(s) return (tostring(s):gsub("%%", "%%%%")) end
  return (line:gsub("{VAR1}", safe(mon)):gsub("{VAR2}", safe(move)))
end
Gen3MoveLearnMenu.fill = fill

local CURSOR = 0x2F   -- the cursor the font stage draws for Hoenn

function Gen3MoveLearnMenu.new(game, mon, newMoveId, onDone)
  local self = setmetatable({}, Gen3MoveLearnMenu)
  self.game = game
  self.mon = mon
  self.newMoveId = newMoveId
  self.onDone = onDone
  self.index = 1
  self.selecting = false
  return self
end

function Gen3MoveLearnMenu:monName()
  local def = self.game.data.pokemon[self.mon.species]
  return self.mon.nickname or (def and def.name) or self.mon.species
end

function Gen3MoveLearnMenu:moveName()
  local def = self.game.data.moves[self.newMoveId]
  return (def and def.name) or self.newMoveId
end

function Gen3MoveLearnMenu:say(role, onClose, opts)
  local TextBox = require("src.render.TextBox")
  local text = fill(Gen3MoveLearnMenu.line(self.game, role),
                    self:monName(), self:moveName())
  self.game.stack:push(TextBox.new(self.game, text, onClose, opts))
end

-- "Should a move be deleted and replaced with {move}?" -- one message, and
-- the question is the last page of it, which is why the choice rides the box
-- rather than being pushed after it.
function Gen3MoveLearnMenu:enter()
  self.selecting = false
  self:say("tryingToLearn", nil, {
    choice = function(yes)
      if not yes then
        self:confirmStop()
        return
      end
      -- EMERALD ASKS ON THE SUMMARY SCREEN, not on a list of its own: the
      -- moves page opens with a cursor and the move being taught sits under
      -- the four as the thing you pick to refuse it.  The list below is kept
      -- as the fallback for a dataset whose summary screen is not there.
      if self:askOnSummary() then return end
      self.selecting = true
    end,
  })
end

-- Returns false when the summary screen cannot be opened, which is the only
-- reason this screen still draws a list of its own.
function Gen3MoveLearnMenu:askOnSummary()
  local ok, Screens = pcall(require, "src.ui.Screens")
  if not ok then return false end
  local okPush, screen = pcall(Screens.push, self.game, "SummaryMenu", {
    mon = self.mon,
    choose = {
      move = self.newMoveId,
      onChoose = function(index) self:chose(index) end,
    },
  })
  return okPush and screen ~= nil
end

-- What the summary screen answered: a slot to forget, or anything else --
-- the fifth row, or B -- meaning the Pokemon should not learn the move.
function Gen3MoveLearnMenu:chose(index)
  local moves = self.mon.moves or {}
  index = tonumber(index)
  if not index or index < 1 or index > math.min(4, #moves) then
    self:confirmStop()
    return
  end
  self:forget(index)
end

-- THE SWAP ITSELF, shared by the summary screen's answer and the fallback
-- list, because an HM refused on one and forgotten on the other would be a
-- rule that depends on which screen asked.
function Gen3MoveLearnMenu:forget(index)
  local moves = self.mon.moves or {}
  local old = moves[index]
  if not old then return end
  -- WHICH MOVES ARE HMs IS THE DATASET'S ANSWER, not this screen's: the
  -- older screen already reads kind == "HM" off constants.machines, which
  -- gives Emerald's eight (DIVE and ROCK SMASH among them, and WHIRLPOOL
  -- not) rather than Johto's.
  local hm = require("src.ui.MoveLearnMenu").hmMoves(self.game)
  if hm[old.id] then
    local TextBox = require("src.render.TextBox")
    self.game.stack:push(TextBox.new(self.game,
      Strings("HM moves can't be\nforgotten now.")))
    return false
  end
  local def = self.game.data.moves[self.newMoveId]
  moves[index] = { id = self.newMoveId, pp = def and def.pp }
  self.forgot = self.game.data.moves[old.id]
  self.forgot = (self.forgot and self.forgot.name) or old.id
  self:finish(true)
  return true
end

-- "Stop trying to teach {move}?" -- and NO comes back to the question, the
-- way the cartridge's own loop does.
function Gen3MoveLearnMenu:confirmStop()
  self.selecting = false
  self:say("stopTeaching", nil, {
    choice = function(yes)
      if yes then self:finish(false) else self:enter() end
    end,
  })
end

function Gen3MoveLearnMenu:update()
  if not self.selecting then return end
  local input = self.game.input
  local moves = self.mon.moves or {}
  local n = #moves + 1        -- the four moves and a way out
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or n
  elseif input:wasPressed("down") then
    self.index = self.index < n and self.index + 1 or 1
  elseif input:wasPressed("b") then
    self:confirmStop()
  elseif input:wasPressed("a") then
    if self.index > #moves then
      self:confirmStop()
      return
    end
    self:forget(self.index)
  end
end

function Gen3MoveLearnMenu:finish(learned)
  local TextBox = require("src.render.TextBox")
  local game = self.game
  self.selecting = false
  game.stack:pop()
  local text
  if learned then
    text = fill(Gen3MoveLearnMenu.line(game, "forgot"), self:monName(),
                self.forgot)
      .. fill(Gen3MoveLearnMenu.line(game, "learned"), self:monName(),
              self:moveName())
  else
    text = fill(Gen3MoveLearnMenu.line(game, "didNotLearn"), self:monName(),
                self:moveName())
  end
  game.stack:push(TextBox.new(game, text, function()
    if self.onDone then self.onDone(learned) end
  end))
end

function Gen3MoveLearnMenu:draw()
  if not self.selecting then return end
  local moves = self.mon.moves or {}
  local rows = #moves + 1
  -- Hoenn's screen is 240x160, so the list sits where there is room for it
  -- rather than at Gen 1's (4,5)
  Font.drawBox(2, 1, 18, rows * 2 + 2)
  love.graphics.setColor(0, 0, 0, 1)
  for i, mv in ipairs(moves) do
    local def = self.game.data.moves[mv.id]
    Font.draw((def and def.name) or mv.id, 32, (2 + i * 2) * 8)
  end
  Font.draw(Strings("CANCEL"), 32, (2 + rows * 2) * 8)
  Font.drawCode(CURSOR, 24, (2 + self.index * 2) * 8)
  -- the question, in the cartridge's own words, in the box it asks from
  Font.drawBox(0, 14, 30, 6)
  Font.draw(Gen3MoveLearnMenu.line(self.game, "whichForget"), 8, 16 * 8)
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3MoveLearnMenu
