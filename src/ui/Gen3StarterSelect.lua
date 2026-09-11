-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- CHOOSING A STARTER, the way Emerald asks.
--
-- Not a list of three words.  The cartridge draws a patch of grass with three
-- Poke Balls sitting on it, a hand you move between them, and the Pokemon's
-- picture and name above whichever one you are pointing at.  A text menu is
-- not a smaller version of that screen, it is a different screen -- and it is
-- the first thing a new game asks the player to do.
--
-- EVERY NUMBER HERE IS THE CARTRIDGE'S.  The extractor finds the whole screen
-- from sStarterMon: the grass is the 256-tile character block beside it, the
-- three ball positions are the six bytes in front of it, the label positions
-- the six bytes behind it, and the balls and the hand are the four 32x32
-- frames in the sheet that follows the grass.  Nothing on this screen is a
-- position somebody eyeballed, which is why moving the balls means re-reading
-- the ROM rather than editing this file.
--
--     constants.gen3StarterSelect = {
--       background = "...png",  sprites = "...png",
--       ballX = { 60, 120, 180 }, ballY = { 64, 88, 64 },
--       labelY = { 32, 56, 32 },  handFrame = 4, ...
--     }
--
-- WHAT IS RECONSTRUCTED: the bounce the balls do, the speed the hand moves,
-- and the fact that the picture is drawn above the ball rather than in a
-- fixed panel.  Those are timing and staging, not data, and they are the
-- part to correct against a recording.
--
-- POINTING AT A BALL IS NOT CHOOSING IT.  The screen has two halves and only
-- the first one was here.  On the cartridge the grass carries nothing but
-- three balls and a hand until A is pressed; then the Pokemon's front picture
-- grows out of the ball it was in, a label window names it and its dex
-- category, and the game ASKS -- "Do you choose this POKeMON?" -- with a
-- YES/NO box.  NO takes the picture away again and hands the player back to
-- the row.
--
-- That confirm step is the whole reason the player sees their starter before
-- the story takes it away: it is the only time in the opening that its
-- picture is on screen.  Without it the first look a player gets at the
-- Pokemon they will carry for sixty hours is a name in a list.
--
-- The question is the CARTRIDGE'S OWN STRING, named by the extractor as the
-- one line in twelve thousand containing "choose this" -- the wording below
-- is only what a cache imported before that existed will show.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3StarterSelect = {}
Gen3StarterSelect.__index = Gen3StarterSelect

local GBA_W, GBA_H = 240, 160

-- RECONSTRUCTED: the ball nearest the hand rocks, on a slow cycle.  The three
-- frames the sheet carries are the whole animation the cartridge has for it.
local BOUNCE_PERIOD = 0.45

Gen3StarterSelect.holdsUIAnchors = true

function Gen3StarterSelect:uiSize() return GBA_W, GBA_H end

local warned = false
local function warnOnce(fmt, ...)
  if warned then return end
  warned = true
  Logger.warn("gen3 starter select: " .. fmt, ...)
end

-- The screen's own record, or nil when this cache predates it.  A dataset
-- without one is not an error -- it is an older import -- so the caller falls
-- back to a plain menu rather than refusing to hand over a starter.
function Gen3StarterSelect.available(game)
  local record = (game and game.data and game.data.constants or {}).gen3StarterSelect
  if type(record) ~= "table" then return nil end
  if not (record.background and record.sprites) then return nil end
  if type(record.ballX) ~= "table" or type(record.ballY) ~= "table" then
    return nil
  end
  return record
end

function Gen3StarterSelect.new(game, species, onChoose)
  local record = Gen3StarterSelect.available(game)
  if not record then return nil end

  local self = setmetatable({}, Gen3StarterSelect)
  self.game = game
  self.record = record
  self.species = species
  self.onChoose = onChoose
  -- the cartridge opens on the middle ball, which is the one that sits
  -- lowest and nearest the player
  self.index = math.min(2, #species)
  self.t = 0
  -- "pick" while the hand is being moved, "confirm" once a ball has been
  -- pressed.  The picture and the question belong to the second one only.
  self.stage = "pick"
  self.picGrow = 0
  self.yes = true

  local okBg, bg = pcall(Assets.image, record.background)
  local okSp, sp = pcall(Assets.image, record.sprites)
  if not (okBg and bg and okSp and sp) then
    warnOnce("the pictures named by the record would not load (%s / %s)",
             tostring(record.background), tostring(record.sprites))
    return nil
  end
  self.bg, self.sheet = bg, sp

  local fw = math.floor(tonumber(record.frameWidth) or 32)
  local fh = math.floor(tonumber(record.frameHeight) or 32)
  local frames = math.max(1, math.floor(tonumber(record.frames) or 1))
  local sw, sh = sp:getDimensions()
  self.frameW, self.frameH = fw, fh
  self.quads = {}
  for i = 1, frames do
    self.quads[i] = love.graphics.newQuad((i - 1) * fw, 0, fw, fh, sw, sh)
  end
  self.handFrame = math.min(frames, math.floor(tonumber(record.handFrame) or frames))
  -- the ball frames are everything up to the hand
  self.ballFrames = math.max(1, self.handFrame - 1)

  -- the background is a 256x256 character block and the screen is the
  -- top-left 240x160 of it
  local bw, bh = bg:getDimensions()
  self.bgQuad = love.graphics.newQuad(0, 0, math.min(GBA_W, bw),
                                      math.min(GBA_H, bh), bw, bh)

  self.pics = {}
  for i, id in ipairs(species) do
    local ok, path = pcall(function()
      return (require("src.pokemon.Sprites").path(game.data, id, "front"))
    end)
    if ok and path then
      local okImg, img = pcall(love.graphics.newImage, path)
      if okImg then self.pics[i] = img end
    end
  end
  return self
end

function Gen3StarterSelect:close(chosen)
  if self.game.stack then self.game.stack:pop() end
  if self.onChoose then self.onChoose(chosen) end
end

-- RECONSTRUCTED: the picture grows out of the ball rather than appearing.
-- The cartridge does it with an affine anim and waits for it to finish before
-- printing the question, which is why the wait is modelled here too -- the
-- question arriving on the same frame as the picture reads as a jump cut.
local GROW_FRAMES = 14

function Gen3StarterSelect:update(dt)
  self.t = (self.t or 0) + (dt or 0)
  local input = self.game.input
  if not input then return end
  local n = #self.species
  if n == 0 then return self:close(nil) end

  if self.stage == "confirm" then
    -- the picture finishes growing before anything can be answered
    if self.picGrow < GROW_FRAMES then
      self.picGrow = self.picGrow + 1
      return
    end
    if input:wasPressed("up") or input:wasPressed("down") then
      self.yes = not self.yes
    elseif input:wasPressed("a") then
      if self.yes then
        self:close(self.species[self.index])
      else
        self.stage, self.picGrow = "pick", 0
      end
    elseif input:wasPressed("b") then
      -- B is NO, exactly as it is on every other yes/no box; it backs out of
      -- the choice, not out of the screen
      self.stage, self.picGrow = "pick", 0
    end
    return
  end

  -- LEFT and RIGHT walk the row; the cartridge also accepts UP and DOWN
  -- because the middle ball sits lower than the other two
  if input:wasPressed("right") or input:wasPressed("down") then
    self.index = self.index % n + 1
  elseif input:wasPressed("left") or input:wasPressed("up") then
    self.index = (self.index - 2) % n + 1
  elseif input:wasPressed("a") then
    self.stage, self.picGrow, self.yes = "confirm", 0, true
  end
  -- NO B. The cartridge does not let the player leave this screen without a
  -- Pokemon, and a script that carries on with an empty party is exactly the
  -- state this screen exists to prevent.
end

-- The question, the cartridge's if this cache has it.
function Gen3StarterSelect:confirmLines()
  local id = self.record and self.record.confirmText
  local raw = id and self.game.data.text and self.game.data.text[id]
  local line = raw or Strings("Do you choose this POKeMON?")
  local out = {}
  for part in tostring(line):gmatch("[^\n]+") do out[#out + 1] = part end
  if #out == 0 then out[1] = tostring(line) end
  return out
end

function Gen3StarterSelect:ballAt(i)
  local r = self.record
  local x = tonumber(r.ballX[i]) or 0
  local y = tonumber(r.ballY[i]) or 0
  return x, y
end

function Gen3StarterSelect:draw()
  love.graphics.setColor(1, 1, 1, 1)
  if self.bg and self.bgQuad then
    love.graphics.draw(self.bg, self.bgQuad, 0, 0)
  end

  local hw, hh = self.frameW / 2, self.frameH / 2

  local i = self.index
  local x, y = self:ballAt(i)
  local labelY = (self.record.labelY and tonumber(self.record.labelY[i]))
                 or (y - 32)

  -- THE PICTURE, and only once a ball has been pressed.  Drawing it under the
  -- hand the whole time is what the screen used to do, and it is the one
  -- thing on this screen that is not a staging choice: the cartridge creates
  -- the sprite in the A-button handler, so before that there is nothing above
  -- the grass at all.
  -- the balls, the chosen one bouncing
  for n = 1, #self.species do
    local bx, by = self:ballAt(n)
    local frame = 1
    local lift = 0
    if n == i and self.ballFrames > 1 then
      local phase = (self.t % BOUNCE_PERIOD) / BOUNCE_PERIOD
      frame = 1 + math.floor(phase * self.ballFrames) % self.ballFrames
      lift = (frame > 1) and -1 or 0
    end
    local quad = self.quads[frame]
    if quad then
      love.graphics.draw(self.sheet, quad,
                         math.floor(bx - hw), math.floor(by - hh + lift))
    end
  end

  local pic = self.stage == "confirm" and self.pics[i] or nil
  if pic then
    local pw, ph = pic:getDimensions()
    local grow = math.min(1, (self.picGrow or 0) / GROW_FRAMES)
    -- eased so it settles rather than stopping dead
    local scale = 0.25 + 0.75 * (1 - (1 - grow) * (1 - grow))
    -- ON THE BALL, which is where the cartridge creates the sprite and where
    -- it grows from.  This used to centre the picture at `labelY - ph/2 - 2`,
    -- putting it ABOVE the label -- and then the label box was drawn after it
    -- and over it, so the player saw a name window with the top of a crest
    -- poking out.
    --
    -- The cartridge's own two tables say where each belongs, and they agree
    -- with each other: the balls are at y 64, 88, 64 and the labels at 32,
    -- 56, 32 -- exactly 32 less, every time, which is half a 64-pixel front
    -- pic.  So the label's y is not a position for the label, it is the
    -- picture's TOP EDGE: the sprite sits centred on its ball and the label
    -- sits directly above it, touching.  Two tables extracted separately
    -- turning out to differ by exactly half a sprite is the check.
    love.graphics.draw(pic, math.floor(x), math.floor(y), 0, scale, scale,
                       pw / 2, ph / 2)
  end

  -- ...AND THE PICTURE OVER THEM.  It used to be drawn BEFORE the balls, so
  -- the ball it is standing on was painted on top of it and the Pokemon
  -- appeared to be behind its own Poke Ball.  On the cartridge the ball opens
  -- and the mon comes OUT: it is in front from the first frame it exists.

  -- the hand, pointing down at the ball
  local quad = self.quads[self.handFrame]
  if quad then
    love.graphics.draw(self.sheet, quad,
                       math.floor(x - hw), math.floor(y - hh - self.frameH + 4))
  end

  -- THE LABEL AND THE QUESTION, which belong to the confirm half too.  The
  -- cartridge's label window carries the dex CATEGORY over the species name
  -- -- "WOOD GECKO" over "TREECKO" -- and it is created in the same handler
  -- that puts the question up, not while the hand is moving.
  if self.stage ~= "confirm" then
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  if (self.picGrow or 0) < GROW_FRAMES then
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  local def = self.game.data.pokemon and self.game.data.pokemon[self.species[i]]
  local name = (def and def.name) or tostring(self.species[i])
  local category = def and def.category

  local glyphH = Font.glyphHeight()
  local inset = math.max(0, math.floor((16 - glyphH) / 2))

  -- the label, over the picture
  do
    local rows = category and { category, name } or { name }
    local widest = 0
    for _, row in ipairs(rows) do widest = math.max(widest, Font.width(row)) end
    local tw = math.max(6, math.ceil(widest / 8) + 2)
    local th = #rows * 2 + 2
    local tx = math.max(0, math.min(30 - tw,
                                    math.floor(x / 8 - tw / 2)))
    -- ITS BOTTOM AT THE PICTURE'S TOP.  labelY is where the front pic begins
    -- (see the note on the picture above), so the box is built upwards from
    -- there and can never reach down over the Pokemon it is naming.  Clamped
    -- to the top of the screen: a taller box is pushed down rather than off,
    -- and the picture keeps its own place either way.
    local ty = math.max(0, math.floor(labelY / 8) - th)
    Font.drawBox(tx, ty, tw, th)
    love.graphics.setColor(0, 0, 0, 1)
    for n, row in ipairs(rows) do
      local rowY = (ty + 1 + (n - 1) * 2) * 8 + inset
      Font.draw(row, math.floor((tx + 1) * 8), rowY)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- the question, in the message window at the foot of the screen
  local lines = self:confirmLines()
  local BOX_TY, BOX_TH = 14, math.max(4, #lines * 2 + 2)
  Font.drawBox(1, BOX_TY, 28, BOX_TH)
  love.graphics.setColor(0, 0, 0, 1)
  for n, line in ipairs(lines) do
    Font.draw(line, 2 * 8, (BOX_TY + 1 + (n - 1) * 2) * 8 + inset)
  end
  love.graphics.setColor(1, 1, 1, 1)

  -- ...and the YES/NO box, which the cartridge puts in the corner above it
  local YES_TX, YES_TY = 23, 8
  Font.drawBox(YES_TX, YES_TY, 6, 6)
  love.graphics.setColor(0, 0, 0, 1)
  for n, label in ipairs({ Strings("YES"), Strings("NO") }) do
    local rowY = (YES_TY + 1 + (n - 1) * 2) * 8 + inset
    Font.draw(label, (YES_TX + 2) * 8, rowY)
    if (self.yes and n == 1) or (not self.yes and n == 2) then
      Font.drawCode(Theme.cursor, (YES_TX + 1) * 8, rowY)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3StarterSelect
