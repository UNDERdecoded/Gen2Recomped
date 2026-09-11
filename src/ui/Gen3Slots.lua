-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- MAUVILLE'S SLOT MACHINES.
--
-- Reported from play: "Also make sure the slots game art and code is properly
-- working in emerald."  Neither existed -- `playslotmachine` was a stub that
-- did nothing and told the script the machine had paid nothing, so every seat
-- in the Game Corner was furniture.
--
-- EVERY NUMBER IN THIS FILE COMES OFF THE CARTRIDGE, through the import's
-- `gen3Slots` record; see extractSlotMachine in RomExtractorGen3 for how each
-- one is found and what it is checked against.  What lives here is the loop:
--
--   * the three reels are the cartridge's own twenty-one-symbol strips, read
--     the way GetTagAtRest reads them -- offset 1, 2 and 3 from a reel's
--     resting position are the top, middle and bottom rows;
--   * a bet of one coin plays the middle row, two adds the top and the
--     bottom, three adds the two diagonals, which is what CheckMatch does
--     with the bet before it looks at anything;
--   * three of a kind pays that symbol's own match, two sevens of a colour
--     followed by one of the other pays the mixed seven, and a CHERRY on the
--     LEFT reel pays on its own -- two coins on the middle row and four off
--     it, which is the one asymmetry in the whole game;
--   * REPLAY pays no coins and buys the next spin, which is why its payout
--     is zero rather than missing.
--
-- WHAT THIS IS NOT, said plainly rather than pretended: the cartridge biases
-- how hard a reel is to stop on a win, and it has a "reel time" bonus round.
-- Neither is modelled.  The reels here stop where you stop them and the RNG
-- is the port's own, so this is a fair machine with Emerald's symbols and
-- Emerald's payouts -- not Emerald's odds.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")

local Gen3Slots = {}
Gen3Slots.__index = Gen3Slots
Gen3Slots.isOpaque = true

-- THE SCREEN THIS IS DRAWN ON, and it has to be asked for.
--
-- Reported from play, with a picture: "not seeing anything on the slot
-- rollers in the slot machine theyre just black", and "its also not aligned
-- properly for widescreen its cutting off the coins in the top right".  One
-- cause, two symptoms.
--
-- Game:draw gives the bigger surface to the states that ASK for it and
-- centres everything else in it, because everything else is laid out in Game
-- Boy coordinates -- so a state with no `uiSize` is moved right by
-- (240-160)/2 = 40 and down by (160-144)/2 = 8.  This file is written in
-- Emerald's 240x160 throughout (it fills 0,0,240,160 and reads its reel
-- windows out of a 256-wide tilemap), and it never said so, so the whole
-- machine was drawn forty pixels to the right: the CREDIT counter ran off the
-- edge with only "CREDI" left of it, which is exactly the report.
--
-- AND THAT IS WHY THE REELS WERE BLACK.  `love.graphics.setScissor` takes
-- CANVAS coordinates and ignores the transform in force -- Gen3Battle's
-- inRegion says the same thing about the same seam -- so with the drawing
-- shifted forty pixels and the clip rectangle not, the symbols were drawn
-- entirely outside the window that was meant to show them.  Every one of them
-- was clipped away, and what was left is the black the screen paints behind
-- the reels.
function Gen3Slots:uiSize() return 240, 160 end

-- WHERE THE MACHINE'S OWN PARTS ARE, measured off the composed screen rather
-- than guessed: the three reel windows are the only places the cartridge's
-- tilemap leaves EMPTY (colour index 0), because the reels are sprites drawn
-- over the backdrop.  They come out at x 32, 72 and 112, thirty-two wide --
-- exactly one symbol -- and y 40 to 111, which is seventy-two: three rows of
-- twenty-four.  The symbol sprite is 32x32 and overhangs its row by four
-- pixels top and bottom, which is why the window clips it.
local REEL_X = { 32, 72, 112 }
local REEL_W = 32
local WINDOW_TOP, WINDOW_H = 40, 72
local ROW = 24                    -- the pitch a reel turns in
local SYMBOL = 32                 -- ...and the sprite drawn on it
local OVERHANG = (SYMBOL - ROW) / 2

-- the two LED counters, found the same way: the tilemap's own unlit digit
-- cells sit at x 179 and 211 on row y 17, four of each at a seven-pixel
-- pitch, and the digit sprite's ink starts one pixel in and three down
local CREDIT_X, PAYOUT_X, COUNTER_Y = 178, 210, 14
local DIGIT_W, DIGIT_PITCH, DIGITS = 8, 7, 4

local SPIN_SPEED = 6              -- pixels a frame while a reel is turning
local MAX_COINS = 9999            -- the coin case's own cap

-- LEAVING THE MACHINE, and the script is told exactly once.  `playslotmachine`
-- blocks the script that ran it, so a path out of this screen that forgets to
-- resume parks the player in a Game Corner they cannot walk out of.
local function leave(self)
  if self.left then return end
  self.left = true
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

local function record(game)
  local constants = game and game.data and game.data.constants
  local slots = constants and constants.gen3Slots
  if type(slots) ~= "table" then return nil end
  if type(slots.reels) ~= "table" or #slots.reels < 3 then return nil end
  return slots
end
Gen3Slots.record = record

local function coins(self)
  return math.max(0, math.floor(tonumber(self.game.save.coins) or 0))
end

local function setCoins(self, n)
  self.game.save.coins = math.max(0, math.min(MAX_COINS, math.floor(n)))
end

-- `opts` is the script's: which seat this is, and what to resume when the
-- player gets up.  A bare number is accepted too, so the screen can be
-- pushed by hand.
function Gen3Slots.new(game, opts)
  local self = setmetatable({}, Gen3Slots)
  if type(opts) ~= "table" then opts = { machineId = opts } end
  self.game = game
  self.cfg = record(game) or {}
  self.machineId = tonumber(opts.machineId) or 0
  self.onDone = opts.onDone
  self.reels = self.cfg.reels or { {}, {}, {} }
  self.tags = self.cfg.tags or 21
  -- a reel's position in PIXELS; at rest it is a whole number of rows
  self.pos = { 0, 0, 0 }
  self.stopped = { true, true, true }
  self.bet = 0
  self.payout = 0
  self.frame = 0
  self.stage = "bet"
  self.message = nil
  self.freeSpin = false
  -- where each reel starts is the only thing here that is random, and it is
  -- rolled once so a machine does not open on the same face every time
  local rng = game.rng or love.math.random
  for reel = 1, 3 do
    self.pos[reel] = rng(0, self.tags - 1) * ROW
  end
  return self
end

-- ---------------------------------------------------------------------------
-- THE REELS
-- ---------------------------------------------------------------------------

-- GetTagAtRest (08:$12BC44): the symbol `offset` rows below reel `reel`'s
-- resting position, wrapping the strip.  Answers nil while the reel is
-- between rows, because there is no symbol on a row that is half past.
function Gen3Slots:tagAtRest(reel, offset)
  local strip = self.reels[reel]
  if not (strip and #strip > 0) then return nil end
  if self.pos[reel] % ROW ~= 0 then return nil end
  local base = math.floor(self.pos[reel] / ROW)
  return strip[((base + offset) % #strip) + 1]
end

function Gen3Slots:spinning()
  return not (self.stopped[1] and self.stopped[2] and self.stopped[3])
end

-- The next reel a press of A would stop, or nil.
function Gen3Slots:nextReel()
  for reel = 1, 3 do
    if not self.stopped[reel] then return reel end
  end
  return nil
end

function Gen3Slots:stopReel(reel)
  if self.stopped[reel] then return end
  -- ...AT THE NEXT ROW, and no further.  The cartridge is allowed to slip a
  -- reel past a symbol to make or break a line; this one is not, so where you
  -- stop it is where it stops.
  local over = self.pos[reel] % ROW
  if over ~= 0 then self.pos[reel] = self.pos[reel] + (ROW - over) end
  self.pos[reel] = self.pos[reel] % (#self.reels[reel] * ROW)
  self.stopped[reel] = true
  Sound.play(self.game.data, "Sfx_StopSlot")
end

-- ---------------------------------------------------------------------------
-- WHAT LINED UP
-- ---------------------------------------------------------------------------

-- GetMatchFromSymbols (08:$12BA6C), stated in the order the cartridge tests
-- it: three the same is that symbol's match; two sevens of one colour
-- followed by one of the other is the mixed seven; a cherry on the LEFT reel
-- pays on its own; anything else pays nothing.
function Gen3Slots:matchOf(a, b, c)
  local cfg = self.cfg
  local none = cfg.noMatch or 9
  if not (a and b and c) then return none end
  if a == b and a == c then
    local m = cfg.symbolMatch and cfg.symbolMatch[a]
    return m or none
  end
  local red, blue = cfg.sevenRed or 0, cfg.sevenBlue or 1
  if (a == red and b == red and c == blue)
     or (a == blue and b == blue and c == red) then
    return cfg.mixed or none
  end
  if a == (cfg.cherry or 4) then return cfg.oneCherry or none end
  return none
end

-- The lines this bet buys, as the three row offsets each one reads.
function Gen3Slots:linesFor(bet)
  local cfg = self.cfg
  local out = {}
  local rows = cfg.rows or { { 1, 1, 1 }, { 2, 2, 2 }, { 3, 3, 3 } }
  local diag = cfg.diagonals or { { 1, 2, 3 }, { 3, 2, 1 } }
  -- CheckMatch (08:$12B828): the centre row always, the top and the bottom
  -- at two coins, the diagonals at three
  out[#out + 1] = { rows[2][1], rows[2][2], rows[2][3], centre = true }
  if bet > 1 then
    out[#out + 1] = { rows[1][1], rows[1][2], rows[1][3] }
    out[#out + 1] = { rows[3][1], rows[3][2], rows[3][3] }
  end
  if bet > 2 then
    for _, d in ipairs(diag) do out[#out + 1] = { d[1], d[2], d[3] } end
  end
  return out
end

-- Everything the stopped reels pay, as {coins, replay, won}.
--
-- `won` is the third answer and it is the one the SCREEN needs: the list of
-- lines that paid, each with the three row offsets it read.  Reported from
-- play: "when winning the slots it should show where you lined them up to
-- win" -- and on a three-coin spin there are five lines it could have been,
-- so a number on its own does not say.
function Gen3Slots:settleLines()
  local cfg = self.cfg
  local none = cfg.noMatch or 9
  local replayMatch = cfg.symbolMatch and cfg.symbolMatch[6]
  local total, replay, won = 0, false, {}
  for index, line in ipairs(self:linesFor(self.bet)) do
    local m = self:matchOf(self:tagAtRest(1, line[1]),
                           self:tagAtRest(2, line[2]),
                           self:tagAtRest(3, line[3]))
    if m ~= none then
      -- OFF THE CENTRE ROW A LONE CHERRY IS WORTH DOUBLE (08:$12B906).  The
      -- cartridge promotes the one-cherry match to the two-cherry one on
      -- every line but the middle, and that promotion is the only difference
      -- between the lines.
      if not line.centre and m == (cfg.oneCherry or 0) then
        m = cfg.twoCherry or m
      end
      local paid = (cfg.payouts and cfg.payouts[m]) or 0
      total = total + paid
      if replayMatch and m == replayMatch then replay = true end
      won[#won + 1] = { index = index, rows = { line[1], line[2], line[3] },
                        match = m, coins = paid }
    end
  end
  return total, replay, won
end

function Gen3Slots:settle()
  local won, replay, lines = self:settleLines()
  self.payout = won
  self.wonLines = (#lines > 0) and lines or nil
  if won > 0 then
    setCoins(self, coins(self) + won)
    self.message = Strings("Lined up!\nWon %d coins!", won)
    Sound.play(self.game.data, "Sfx_GetCoinFromSlots")
  elseif replay then
    self.message = Strings("REPLAY!\nOne more spin, free.")
  else
    self.message = Strings("Darn…")
  end
  self.freeSpin = replay
  self.stage = "result"
end

-- ---------------------------------------------------------------------------
-- THE LOOP
-- ---------------------------------------------------------------------------

function Gen3Slots:startSpin()
  self.stopped = { false, false, false }
  self.payout = 0
  self.wonLines = nil
  self.message = nil
  self.stage = "spin"
  Sound.play(self.game.data, "Sfx_SlotMachineStart")
end

function Gen3Slots:insert(n)
  local want = math.min(self.cfg.maxBet or 3, self.bet + n)
  local extra = want - self.bet
  if extra <= 0 then return end
  if self.freeSpin then
    -- a REPLAY has already paid for this spin, at the bet it was won on
    self.bet = want
    return
  end
  extra = math.min(extra, coins(self))
  if extra <= 0 then
    self.message = Strings("You don't have\nenough coins.")
    return
  end
  setCoins(self, coins(self) - extra)
  self.bet = self.bet + extra
  Sound.play(self.game.data, "Sfx_SlotMachineStart")
end

function Gen3Slots:update()
  local input = self.game.input
  self.frame = (self.frame or 0) + 1

  if self.stage == "bet" then
    if input:wasPressed("b") then return leave(self) end
    if input:wasPressed("select") then self.stage = "info" return end
    if input:wasPressed("a") or input:wasPressed("up")
       or input:wasPressed("down") then
      self:insert(1)
      return
    end
    if input:wasPressed("start") then
      if self.bet == 0 then self:insert(self.cfg.maxBet or 3) end
      if self.bet > 0 then self:startSpin() end
    end
    return
  end

  if self.stage == "info" then
    if input:wasPressed("a") or input:wasPressed("b")
       or input:wasPressed("select") then
      self.stage = "bet"
    end
    return
  end

  if self.stage == "spin" then
    for reel = 1, 3 do
      if not self.stopped[reel] then
        local span = #self.reels[reel] * ROW
        self.pos[reel] = (self.pos[reel] + SPIN_SPEED) % span
      end
    end
    if input:wasPressed("a") then
      local reel = self:nextReel()
      if reel then self:stopReel(reel) end
      if not self:spinning() then self:settle() end
    end
    return
  end

  if self.stage == "result" then
    if input:wasPressed("a") or input:wasPressed("b") then
      self.bet = self.freeSpin and self.bet or 0
      if not self.freeSpin and coins(self) <= 0 then
        self.message = Strings("You've run out\nof coins.")
        self.stage = "broke"
        return
      end
      self.stage = "bet"
      self.message = nil
    end
    return
  end

  if self.stage == "broke" then
    if input:wasPressed("a") or input:wasPressed("b") then
      leave(self)
    end
  end
end

-- ---------------------------------------------------------------------------
-- DRAWING
-- ---------------------------------------------------------------------------

function Gen3Slots:loadArt()
  if self.artLoaded then return end
  self.artLoaded = true
  local Assets = require("src.render.Assets")
  local function image(path)
    if type(path) ~= "string" then return nil end
    local ok, img = pcall(Assets.image, path)
    return ok and img or nil
  end
  self.bgImg = image(self.cfg.background)
  self.symbolImg = {}
  for i = 0, (self.cfg.symbols or 7) - 1 do
    self.symbolImg[i] = image(self.cfg.symbolArt and self.cfg.symbolArt[i])
  end
  self.digitImg = image(self.cfg.digitArt)
end

function Gen3Slots:drawReels()
  local g = love.graphics
  for reel = 1, 3 do
    local strip = self.reels[reel]
    if strip and #strip > 0 then
      local span = #strip * ROW
      local base = math.floor(self.pos[reel] / ROW)
      local frac = self.pos[reel] % ROW
      g.setScissor(REEL_X[reel], WINDOW_TOP, REEL_W, WINDOW_H)
      -- one row past each edge, so a reel between rows is never short
      for r = 0, 4 do
        local tag = strip[((base + r) % #strip) + 1]
        local img = self.symbolImg and self.symbolImg[tag]
        if img then
          g.setColor(1, 1, 1, 1)
          g.draw(img, REEL_X[reel],
                 WINDOW_TOP + (r - 1) * ROW - frac - OVERHANG)
        end
      end
      g.setScissor()
      local _ = span
    end
  end
end

function Gen3Slots:drawCounter(x, value)
  local text = ("%04d"):format(math.max(0, math.min(9999, value or 0)))
  local img = self.digitImg
  for i = 1, DIGITS do
    local d = tonumber(text:sub(i, i)) or 0
    if img then
      local iw, ih = img:getDimensions()
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img,
        love.graphics.newQuad(d * DIGIT_W, 0, DIGIT_W, ih, iw, ih),
        x + (i - 1) * DIGIT_PITCH, COUNTER_Y)
    else
      love.graphics.setColor(1, 0.85, 0.2, 1)
      Font.draw(text:sub(i, i), x + (i - 1) * DIGIT_PITCH, COUNTER_Y + 3)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- WHERE THE MACHINE'S PARTS ARE.  The import measures the three reel windows
-- off the tilemap -- they are the only holes the backdrop leaves, because the
-- reels are sprites drawn over it -- and the constants at the top of this
-- file are what it produced, kept as the answer for a cache imported before
-- the stage could measure them.
function Gen3Slots:geometry()
  local screen = self.cfg and self.cfg.screen
  local w = screen and screen.windows
  if type(w) == "table" and #w == 3 and screen.top and screen.rowPitch then
    return { x = { w[1].x, w[2].x, w[3].x }, w = w[1].w,
             top = screen.top, pitch = screen.rowPitch }
  end
  return { x = REEL_X, w = REEL_W, top = WINDOW_TOP, pitch = ROW }
end

-- ...and the five paylines, in the order linesFor hands them out.
function Gen3Slots:paylines()
  local screen = self.cfg and self.cfg.screen
  local lines = screen and screen.lines
  return (type(lines) == "table" and #lines >= 5) and lines or nil
end

local function inkOf(colour, alpha)
  love.graphics.setColor(colour[1] / 255, colour[2] / 255, colour[3] / 255,
                         alpha or 1)
end

-- THE PAYLINES THIS BET HAS BOUGHT, lit on the machine's own markers.
--
-- The markers are already there: the cartridge draws all five into the
-- tilemap, in the gaps between the reel windows and outside the outer two,
-- and the colour is the PRICE -- blue for the coin that buys the middle row,
-- yellow for the one that buys the top and the bottom, red for the one that
-- buys the diagonals.  What lighting them means here is painting the
-- cartridge's own segments in the cartridge's own colour, at the cartridge's
-- own thickness, all of which the import measured.
--
-- AND IT NO LONGER TOUCHES THE REELS.  This used to wash a translucent
-- yellow band across all three windows, which tinted the symbols underneath
-- and is not something the machine does at all.
function Gen3Slots:drawBetLamps()
  local lit = self.bet
  local lines = self:paylines()
  if lit <= 0 or not lines then return end
  local g = love.graphics
  for _, line in ipairs(lines) do
    if (line.coins or 1) <= lit and line.segments and line.y then
      local tall = math.max(2, math.floor((line.thickness or 4) / 2))
      for _, seg in ipairs(line.segments) do
        inkOf(line.shadow or line.color, 1)
        g.rectangle("fill", seg.x, line.y - tall, seg.w, tall)
        inkOf(line.color, 1)
        g.rectangle("fill", seg.x, line.y, seg.w, tall)
      end
    end
  end
  g.setColor(1, 1, 1, 1)
end

-- WHICH LINE PAID, drawn along the three cells that matched.
--
-- Reported from play: "when winning the slots it should show where you lined
-- them up to win".  The machine could say how much it had paid and not why,
-- and on a three-coin spin that is five lines it could have been.  So the
-- line is drawn through the middle of the three symbols that made it, in its
-- own colour off the marker that sells it -- which is what ties the flash on
-- the reels to the marker at the edge -- and it flashes, so a still frame
-- never hides it and a moving one cannot be mistaken for part of the art.
function Gen3Slots:drawWinLines()
  local won = self.wonLines
  if not (won and #won > 0) then return end
  if math.floor((self.frame or 0) / 8) % 2 == 1 then return end
  local geo = self:geometry()
  local lines = self:paylines()
  local g = love.graphics
  for _, win in ipairs(won) do
    local mark = lines and lines[win.index]
    local colour = (mark and mark.color) or { 255, 255, 255 }
    local shadow = (mark and mark.shadow) or { 0, 0, 0 }
    -- from the left edge of the first window to the right edge of the last,
    -- through the centre of each matched cell
    local function cellY(i)
      return geo.top + geo.pitch * ((win.rows[i] or 1) - 1)
             + math.floor(geo.pitch / 2)
    end
    local points = {
      geo.x[1], cellY(1),
      geo.x[1] + geo.w / 2, cellY(1),
      geo.x[2] + geo.w / 2, cellY(2),
      geo.x[3] + geo.w / 2, cellY(3),
      geo.x[3] + geo.w, cellY(3),
    }
    local shifted = {}
    for i = 1, #points, 2 do
      shifted[i], shifted[i + 1] = points[i], points[i + 1] + 1
    end
    g.setLineWidth(4)
    inkOf(shadow, 1)
    g.line(shifted)
    g.setLineWidth(2)
    inkOf(colour, 1)
    g.line(points)
  end
  g.setLineWidth(1)
  g.setColor(1, 1, 1, 1)
end

function Gen3Slots:drawMessage()
  local text = self.message
  if self.stage == "bet" and not text then
    text = self.freeSpin and Strings("REPLAY -- press START.")
           or Strings("Bet how many coins?")
  elseif self.stage == "spin" and not text then
    text = Strings("Press A to stop a reel.")
  end
  if not text then return end
  love.graphics.setColor(0, 0, 0, 0.72)
  love.graphics.rectangle("fill", 8, 118, 224, 34)
  love.graphics.setColor(1, 1, 1, 1)
  local row = 0
  for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
    if row < 2 then Font.draw(line, 14, 122 + row * 14) end
    row = row + 1
  end
end

function Gen3Slots:drawInfo()
  local cfg = self.cfg
  local g = love.graphics
  g.setColor(0, 0, 0, 0.86)
  g.rectangle("fill", 8, 8, 224, 144)
  g.setColor(1, 1, 1, 1)
  Font.draw(Strings("PAYOUTS"), 16, 14)
  local names = { "7 (RED)", "7 (BLUE)", "AZURILL", "LOTAD", "CHERRY",
                  "POWER", "REPLAY" }
  local y = 32
  for tag = 0, (cfg.symbols or 7) - 1 do
    local img = self.symbolImg and self.symbolImg[tag]
    if img then g.draw(img, 18, y - 6, 0, 0.5, 0.5) end
    Font.draw(names[tag + 1] or ("#" .. tag), 40, y)
    local m = cfg.symbolMatch and cfg.symbolMatch[tag]
    local pay = m and cfg.payouts and cfg.payouts[m]
    Font.draw(pay == 0 and Strings("FREE SPIN") or tostring(pay or "?"),
              160, y)
    y = y + 16
  end
  Font.draw(Strings("A CHERRY ON THE LEFT REEL PAYS ALONE."), 16, y + 2)
end

function Gen3Slots:draw()
  self:loadArt()
  local g = love.graphics
  -- the machine's backdrop, which is the colour the reel windows and the
  -- right-hand panel show through as
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, 240, 160)
  g.setColor(1, 1, 1, 1)
  self:drawReels()
  if self.bgImg then g.draw(self.bgImg, 0, 0) end
  self:drawBetLamps()
  self:drawWinLines()
  self:drawCounter(CREDIT_X, coins(self))
  self:drawCounter(PAYOUT_X, self.payout or 0)
  if self.stage == "info" then
    self:drawInfo()
  else
    self:drawMessage()
  end
end

return Gen3Slots
