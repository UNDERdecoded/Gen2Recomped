-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- EMERALD'S CREDITS.
--
-- The port had a credits screen and it was the GAME BOY's -- its own
-- copyright tiles, its own scrolling Pokemon, its own three screens of Kanto
-- staff -- so the end of Hoenn had nothing to roll.
--
-- THE ROLL IS PAGES, NOT A LIST, and that is the whole reason this file is
-- shaped the way it is.  The cartridge keeps TWO tables: a flat array of
-- entries, and sCreditsEntryPointerTable, which is FIVE POINTERS PER PAGE
-- into that array.  Fifty-seven pages of five, and the same heading record is
-- pointed at from several consecutive pages -- which is how "Programmers"
-- stays on screen while four different names change under it.  Rolling the
-- flat array instead loses that completely and turns a heading and nine names
-- into ten equal lines with no idea which was which.
--
-- WHAT THIS IS NOT, said plainly rather than pretended: the cartridge's
-- credits are a SCENE.  The player and their rival walk across a moving
-- Hoenn behind the text, the music is scored to the length of it, and it ends
-- on the title screen.  This shows the same fifty-seven pages in the same
-- order with the same headings, and then ends -- which is a credits sequence,
-- and is not Emerald's.

local Font = require("src.render.Font")
local Music = require("src.core.Music")

local Gen3Credits = {}
Gen3Credits.__index = Gen3Credits
Gen3Credits.isOpaque = true

local GBA_W, GBA_H = 240, 160
function Gen3Credits:uiSize() return GBA_W, GBA_H end

-- A page holds, then the next one takes over.  Fifty-seven pages at three
-- seconds each is a little under three minutes, which is about the length of
-- the cartridge's own roll.
local HOLD = 180            -- frames a page stays up
local FADE = 24             -- ...of which the first and last are a fade
local LEAD_IN = 60          -- frames of black before the first page
local TAIL = 120            -- ...and after the last
local LINE_H = 18           -- the five rows, centred as a block

-- A HEADING IS THE ONE THE RECORD SAYS IS ONE.  `isTitle` is the second byte
-- of every entry; the first pass through this read the wrong byte and got the
-- attributes one record late, so headings and names were swapped almost at
-- random.  They are drawn in different colours because the cartridge does.
local TITLE_RGB = { 0.98, 0.84, 0.35 }
local NAME_RGB  = { 1, 1, 1 }

function Gen3Credits.record(game)
  local c = game and game.data and game.data.constants
  local r = c and c.gen3Credits
  if type(r) ~= "table" then return nil end
  if type(r.pages) == "table" and #r.pages > 0 then return r end
  return nil
end

function Gen3Credits.new(game, onDone)
  local record = Gen3Credits.record(game)
  if not record then return nil end
  local self = setmetatable({}, Gen3Credits)
  self.game = game
  self.onDone = onDone
  self.pages = record.pages
  self.frame = -LEAD_IN
  self.done = false
  return self
end

function Gen3Credits:enter()
  -- the credits have their own music where the dataset names one; the
  -- Hall of Fame's is what plays if it does not
  local ok = pcall(Music.play, self.game.data, "Music_Credits")
  if not ok then pcall(Music.play, self.game.data, "Music_HallOfFame") end
end

function Gen3Credits:finish()
  if self.done then return end
  self.done = true
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

-- Which page is up, and how solid it is.  Returns nil past the end.
function Gen3Credits:at(frame)
  frame = frame or self.frame
  if frame < 0 then return nil, 0 end
  local index = math.floor(frame / HOLD) + 1
  if index > #self.pages then return nil, 0 end
  local into = frame - (index - 1) * HOLD
  local alpha = 1
  if into < FADE then alpha = into / FADE
  elseif into > HOLD - FADE then alpha = (HOLD - into) / FADE end
  return index, alpha
end

function Gen3Credits:update()
  self.frame = (self.frame or 0) + 1
  local total = #self.pages * HOLD + TAIL
  if self.frame >= total then return self:finish() end
  -- START skips to the end, the way every long unskippable thing in this
  -- port lets you out of it
  local input = self.game.input
  if input and input.wasPressed and input:wasPressed("start") then
    self.frame = total
  end
end

function Gen3Credits:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, GBA_W, GBA_H)
  local index, alpha = self:at()
  local page = index and self.pages[index]
  if not page then g.setColor(1, 1, 1, 1) return end
  local faced = Font.pushFace("small")
  -- the five rows are a block in the middle of the screen, blanks included,
  -- because the blanks are how the cartridge spaces a short page
  local top = math.floor((GBA_H - #page * LINE_H) / 2)
  for row, entry in ipairs(page) do
    local text = tostring(entry.text or "")
    if text ~= "" then
      local rgb = entry.title and TITLE_RGB or NAME_RGB
      g.setColor(rgb[1], rgb[2], rgb[3], alpha)
      local w = Font.width(text)
      Font.draw(text, math.floor((GBA_W - w) / 2), top + (row - 1) * LINE_H)
    end
  end
  if faced then Font.popFace() end
  g.setColor(1, 1, 1, 1)
end

function Gen3Credits:keypressed() end

return Gen3Credits
