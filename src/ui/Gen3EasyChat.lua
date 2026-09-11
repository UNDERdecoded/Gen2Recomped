-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE EASY CHAT SCREEN -- gSpecials[98], and the nineteen places that call it.
--
-- Nobody in Hoenn types a sentence.  A phrase is two to six word ids picked
-- out of twenty-two groups, and this one screen is how every one of them is
-- chosen: the four Mauville old men, the QUIZ LADY's question, DEWFORD's
-- trend, the interviews, a secret base's greeting, and every piece of mail.
-- VAR_0x8004 says which caller it is, and the caller's arm inside the special
-- decides how many slots there are and where the words are written back.
--
-- WHAT THIS IS NOT, said plainly rather than pretended: the cartridge's own
-- screen is a GRID -- the phrase across the top, a page of words underneath,
-- an alphabetical mode, a group tab per row and a keyboard-shaped cursor that
-- walks all of it.  This picks the same words out of the same groups through
-- this port's own list menu: a row per slot showing what is in it, then a
-- group, then a word.  The phrase that comes out is identical; the screen it
-- was chosen on is not.
--
-- THE EMPTY SLOT IS A REAL VALUE.  A phrase shorter than its slots is spelled
-- with $FFFF, which is what the cartridge writes for "nothing here" and what
-- every reader of one of these treats as the end -- so backing out of a word
-- has to write that rather than leaving the old one behind.

local Menu = require("src.ui.Menu")
local Strings = require("src.core.Strings")
local EasyChat = require("src.script.EasyChat")

local Gen3EasyChat = {}

Gen3EasyChat.EMPTY = 0xFFFF
local VISIBLE = 7

local function label(game, word)
  if word == nil or word == Gen3EasyChat.EMPTY then return "------" end
  return EasyChat.text(game.data, word) or "------"
end

-- Every menu here pushes a FRESH one rather than keeping the last open: the
-- port's Menu pops itself on select, which is the same shape the PC's own
-- screens use.
local function push(game, rows, onCancel, visible)
  local items = {}
  for i, row in ipairs(rows) do
    items[i] = { label = row.label, onSelect = row.onSelect }
  end
  local ok = pcall(game.stack.push, game.stack,
                   Menu.new(game, items,
                            { tx = 0, ty = 0, onCancel = onCancel,
                              maxVisible = visible or VISIBLE }))
  if not ok and onCancel then onCancel() end
  return ok
end

local function pickWord(self, slot, groupIndex, back)
  local words = EasyChat.words(self.game.data, groupIndex, self.game.save)
  local rows = {}
  for _, w in ipairs(words) do
    rows[#rows + 1] = {
      label = w.text,
      onSelect = function()
        self.words[slot] = w.id
        self:slots()
      end,
    }
  end
  -- ...and a way to empty the slot, which is how a phrase gets to be shorter
  -- than the room it is written in
  rows[#rows + 1] = {
    label = Strings("(NOTHING)"),
    onSelect = function()
      self.words[slot] = Gen3EasyChat.EMPTY
      self:slots()
    end,
  }
  push(self.game, rows, back)
end

local function pickGroup(self, slot, back)
  local names = EasyChat.groupNames(self.game.data)
  local rows = {}
  for i, name in ipairs(names) do
    local g = i - 1
    -- a group with nothing in it is left OFF the list rather than
    -- offered and then found empty -- which is what the trendy
    -- sayings look like until the HIPSTER has spoken
    if #EasyChat.words(self.game.data, g, self.game.save) > 0 then
      rows[#rows + 1] = {
        label = name,
        onSelect = function()
          pickWord(self, slot, g, function() pickGroup(self, slot, back) end)
        end,
      }
    end
  end
  push(self.game, rows, back)
end

-- The top of the screen: one row per slot, then the two ways out.
function Gen3EasyChat:slots()
  local rows = {}
  for i = 1, self.count do
    local slot = i
    rows[#rows + 1] = {
      label = label(self.game, self.words[slot]),
      onSelect = function()
        pickGroup(self, slot, function() self:slots() end)
      end,
    }
  end
  rows[#rows + 1] = { label = Strings("DONE"),
                      onSelect = function() self:finish(true) end }
  rows[#rows + 1] = { label = Strings("CANCEL"),
                      onSelect = function() self:finish(false) end }
  push(self.game, rows, function() self:finish(false) end, self.count + 2)
end

function Gen3EasyChat:finish(kept)
  if self.done then return end
  self.done = true
  if kept and self.onDone then return self.onDone(self.words) end
  if not kept and self.onCancel then return self.onCancel() end
end

-- `words` is what the slots open on -- the cartridge copies the phrase being
-- edited into the audition slot first, so the screen shows what is already
-- there rather than six blanks.
function Gen3EasyChat.open(game, opts)
  opts = opts or {}
  if not (game and game.stack and EasyChat.record(game.data)) then
    if opts.onCancel then opts.onCancel() end
    return nil
  end
  local self = setmetatable({}, { __index = Gen3EasyChat })
  self.game = game
  self.count = math.max(1, math.floor(tonumber(opts.count) or 6))
  self.onDone, self.onCancel = opts.onDone, opts.onCancel
  self.words = {}
  for i = 1, self.count do
    local w = (opts.words or {})[i]
    self.words[i] = (w and w ~= Gen3EasyChat.EMPTY) and w or Gen3EasyChat.EMPTY
  end
  self:slots()
  return self
end

return Gen3EasyChat
