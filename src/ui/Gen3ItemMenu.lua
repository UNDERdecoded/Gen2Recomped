-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHAT TO DO WITH THE ITEM YOU JUST PICKED.
--
-- Emerald's bag does not act on a choice: it opens a small grid in the corner
-- and asks.  What the grid offers depends on the pocket -- a POKe BALL cannot
-- be USED from the bag, a TM cannot be TOSSED, a KEY ITEM can be REGISTERED
-- and nothing else, a BERRY offers CHECK TAG above everything -- and the five
-- lists come out of the cartridge (RomExtractorGen3:itemMenuActions).
--
-- TWO COLUMNS, AND THE BLANK IS PART OF IT.  The cartridge lays the actions
-- out two across, and one of its actions is a deliberately empty cell that
-- holds a hole open so the rest line up: the KEY ITEM list is USE, REGISTER,
-- (nothing), CANCEL, which puts CANCEL under REGISTER rather than under USE.
-- Dropping the blank would move it, so the blank is drawn as a gap and
-- skipped by the cursor.
--
-- This screen only ASKS.  What each answer does belongs to the bag, which is
-- what holds the item and the list to refresh, so the pick comes back as a
-- kind ("use", "toss", "give", "register", "cancel") and the bag acts on it.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Theme = require("src.ui.Theme")

local Gen3ItemMenu = {}
Gen3ItemMenu.__index = Gen3ItemMenu

local GBA_W, GBA_H = 240, 160
local COL_W = 7          -- tiles per column, including its gap
local ROW_PITCH = 16     -- pixels per row, as the bag's list uses

function Gen3ItemMenu:uiSize() return GBA_W, GBA_H end
function Gen3ItemMenu:wantsFillScale() return true end

-- entries: { { label = "USE", kind = "use" }, ... } in the cartridge's own
-- order, blanks included.  onPick(kind, index) is called with the pick; a
-- cancel (B, or the CANCEL cell) calls it with "cancel".
function Gen3ItemMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen3ItemMenu)
  self.game = game
  self.entries = opts.entries or {}
  self.columns = math.max(1, math.floor(tonumber(opts.columns) or 2))
  self.onPick = opts.onPick
  self.rows = math.ceil(#self.entries / self.columns)

  -- the window: as wide as its columns and as tall as its rows, tucked into
  -- the bottom-right corner the way the cartridge tucks it
  self.tw = self.columns * COL_W + 2
  self.th = self.rows * 2 + 2
  self.tx = math.floor(GBA_W / 8) - self.tw
  self.ty = math.floor(GBA_H / 8) - self.th

  self.index = self:firstPickable()
  return self
end

function Gen3ItemMenu:pickable(i)
  local e = self.entries[i]
  return e ~= nil and e.kind ~= "blank" and (e.label or "") ~= ""
end

function Gen3ItemMenu:firstPickable()
  for i = 1, #self.entries do
    if self:pickable(i) then return i end
  end
  return 1
end

-- MOVING ON A GRID WITH HOLES IN IT.  A step that lands on the blank keeps
-- going the same way rather than stopping on nothing, and a step off the end
-- wraps -- which is what the cartridge's cursor does.
function Gen3ItemMenu:step(dir)
  local n = #self.entries
  if n == 0 then return false end
  local cols, rows = self.columns, self.rows
  local r = math.floor((self.index - 1) / cols)
  local c = (self.index - 1) % cols
  for _ = 1, math.max(cols, rows) do
    if dir == "up" then r = (r - 1) % rows
    elseif dir == "down" then r = (r + 1) % rows
    elseif dir == "left" then c = (c - 1) % cols
    elseif dir == "right" then c = (c + 1) % cols
    else return false end
    local i = r * cols + c + 1
    if self:pickable(i) then
      self.index = i
      return true
    end
  end
  return false
end

function Gen3ItemMenu:close(kind)
  if self.game.stack then self.game.stack:pop() end
  if self.onPick then self.onPick(kind or "cancel", self.index) end
end

function Gen3ItemMenu:update()
  local input = self.game.input
  if not input then return end
  if input:wasPressed("b") then
    Sound.play(self.game.data, "Press_AB")
    return self:close("cancel")
  end
  if input:wasPressed("a") then
    Sound.play(self.game.data, "Press_AB")
    local e = self.entries[self.index]
    return self:close(e and e.kind or "cancel")
  end
  for _, dir in ipairs({ "up", "down", "left", "right" }) do
    if input:wasPressed(dir) then
      self:step(dir)
      return
    end
  end
end

function Gen3ItemMenu:keypressed(key)
  if key == "b" then return self:close("cancel") end
  if key == "a" then
    local e = self.entries[self.index]
    return self:close(e and e.kind or "cancel")
  end
  self:step(key)
end

function Gen3ItemMenu:draw()
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(self.tx, self.ty, self.tw, self.th)
  for i, entry in ipairs(self.entries) do
    local r = math.floor((i - 1) / self.columns)
    local c = (i - 1) % self.columns
    local x = (self.tx + 1) * 8 + c * COL_W * 8 + 8
    local y = (self.ty + 1) * 8 + r * ROW_PITCH
    if (entry.label or "") ~= "" then
      Font.draw(entry.label, x, y)
    end
    if i == self.index then
      Font.drawCode(Theme.cursor, x - 8, y)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3ItemMenu
