-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- MAUVILLE'S ROULETTE, the other half of the Game Corner.
--
-- Reported from play: "nobody in the gamecorner is recognizing that i have a
-- coin case".  That was one bug and it hid two rooms: the slot machines,
-- which now work, and the two roulette tables, which had nothing behind them
-- at all -- gSpecials[165] was not served.
--
-- THE BOARD IS TWELVE SQUARES IN THREE ROWS OF FOUR, and every number in
-- this file comes off the cartridge through `constants.gen3Roulette`; see
-- extractRoulette in RomExtractorGen3 for how each is found and checked.
-- What lives here is the game:
--
--   * you may bet on ONE SQUARE, on a COLUMN (the four headers along the
--     top) or on a ROW (the three down the left side);
--   * the ball lands on one of the twelve squares, and that square is then
--     STRUCK OFF for the rest of the sitting;
--   * a bet pays twelve coins for every one staked, divided by how many of
--     its squares are still standing -- so a row starts at three to one and
--     is worth twelve to one once three of its four are gone, and a bet
--     whose squares have all been struck pays nothing at all.
--
-- That last rule is not a house rule invented here.  GetMultiplier
-- (0x0142758) reads sPayouts { 0, 3, 4, 6, 12 } by the number of squares the
-- bet still covers, and every entry times its coverage is twelve.
--
-- THE STAKE is the table's, off VAR_0x8004: table one costs one coin a spin
-- and table two three, and on the Game Corner's service day table two costs
-- six.  The script refuses to seat you with fewer coins than that, and so
-- does this.
--
-- WHAT THIS IS NOT, said plainly: the cartridge draws a spinning wheel with
-- a ball you can watch, and its landing is a physics-ish settle rather than
-- a roll.  This spins the wheel for show and then picks a square uniformly.
-- The BOARD, the payouts and the striking-off are the cartridge's; the feel
-- of the wheel is the port's.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3Roulette = {}
Gen3Roulette.__index = Gen3Roulette
Gen3Roulette.isOpaque = true

local GBA_W, GBA_H = 240, 160

-- the board, laid out as the cartridge lays it out: a header column down the
-- left and a header row across the top, with the twelve squares inside
local CELL_W, CELL_H = 34, 26
local BOARD_X, BOARD_Y = 62, 34
local HEAD_W, HEAD_H = 26, 20

Gen3Roulette.SPIN_FRAMES = 96      -- how long the wheel turns before it lands
Gen3Roulette.SETTLE_FRAMES = 24    -- ...and how long it sits on the answer
Gen3Roulette.WHEEL_STEPS = 24      -- the cartridge's wheel is twenty-four

local function record(game)
  local constants = game and game.data and game.data.constants
  local r = constants and constants.gen3Roulette
  if type(r) ~= "table" or type(r.board) ~= "table" or #r.board == 0 then
    return nil
  end
  return r
end
Gen3Roulette.record = record

local function leave(self)
  if self.left then return end
  self.left = true
  if self.game.stack then self.game.stack:pop() end
  if self.onDone then self.onDone() end
end

function Gen3Roulette:uiSize() return GBA_W, GBA_H end
function Gen3Roulette:wantsFillScale() return true end

-- WHICH STAKE THIS TABLE ASKS.  sMinBets is indexed by the low bit of
-- VAR_0x8004 -- which of the two tables you sat at -- plus two when bit 7 is
-- set, which is the Game Corner's service day (0x0142AA6).
function Gen3Roulette.stakeFor(cfg, selector)
  local bets = cfg and cfg.bets
  if type(bets) ~= "table" or #bets < 4 then return 1 end
  local sel = math.floor(tonumber(selector) or 0)
  local index = (sel % 2) + (math.floor(sel / 128) % 2) * 2
  return math.max(1, math.floor(tonumber(bets[index + 1]) or 1))
end

function Gen3Roulette.new(game, opts)
  local self = setmetatable({}, Gen3Roulette)
  if type(opts) ~= "table" then opts = { selector = opts } end
  self.game = game
  self.cfg = record(game) or {}
  self.onDone = opts.onDone
  self.selector = math.floor(tonumber(opts.selector) or 0)
  self.stake = Gen3Roulette.stakeFor(self.cfg, self.selector)
  self.rng = opts.rng or game.rng or love.math.random

  -- the nineteen places a bet can go: three rows, four columns, twelve
  -- squares.  A bet is named by its KIND and its index, which is all the
  -- payout needs.
  self.rows = math.max(1, math.floor(tonumber(self.cfg.rows) or 3))
  self.columns = math.max(1, math.floor(tonumber(self.cfg.columns) or 4))
  self.cursor = { kind = "square", row = 0, column = 0 }
  self.standing = {}                 -- square id -> still on the board
  for _, sq in ipairs(self.cfg.board or {}) do self.standing[sq.id] = true end

  self.stage = "bet"
  self.frame = 0
  self.angle = 0
  self.landed = nil
  self.payout = 0
  self.message = nil
  return self
end

-- ---------------------------------------------------------------------------
-- THE BOARD
-- ---------------------------------------------------------------------------

-- The square in a cell, by the Chinese-remainder placement the cartridge
-- uses: square n sits in row n mod 3 and column n mod 4, which is a bijection
-- because three and four are coprime.
function Gen3Roulette:squareAt(row, column)
  for _, sq in ipairs(self.cfg.board or {}) do
    if sq.row == row and sq.column == column then return sq end
  end
  return nil
end

-- How many of a bet's squares are still standing.
function Gen3Roulette:coverage(bet)
  local n = 0
  for _, sq in ipairs(self.cfg.board or {}) do
    local covered = (bet.kind == "square"
                     and sq.row == bet.row and sq.column == bet.column)
                    or (bet.kind == "row" and sq.row == bet.row)
                    or (bet.kind == "column" and sq.column == bet.column)
    if covered and self.standing[sq.id] then n = n + 1 end
  end
  return n
end

-- ...and what that coverage pays, which is twelve over it.
function Gen3Roulette:multiplier(bet)
  local left = self:coverage(bet)
  if left <= 0 then return 0 end
  local table_ = self.cfg.payouts
  local pays = type(table_) == "table" and tonumber(table_[left]) or nil
  if pays then return pays end
  local squares = math.floor(tonumber(self.cfg.squares) or 12)
  return math.floor(squares / left)
end

-- ---------------------------------------------------------------------------
-- THE CURSOR
-- ---------------------------------------------------------------------------

-- The board is walked as a grid with the headers in it: the top row is the
-- four column headers and the left column the three row headers, so moving
-- up out of a square lands on its column's header and moving left lands on
-- its row's.
function Gen3Roulette:moveCursor(dx, dy)
  local c = self.cursor
  local col = (c.kind == "row") and -1 or c.column
  local row = (c.kind == "column") and -1 or c.row
  col = math.max(-1, math.min(self.columns - 1, col + dx))
  row = math.max(-1, math.min(self.rows - 1, row + dy))
  -- the corner is not a bet; slide it back onto the board
  if col < 0 and row < 0 then
    if dx ~= 0 then col = 0 else row = 0 end
  end
  if col < 0 then
    self.cursor = { kind = "row", row = row, column = 0 }
  elseif row < 0 then
    self.cursor = { kind = "column", row = 0, column = col }
  else
    self.cursor = { kind = "square", row = row, column = col }
  end
  Sound.play(self.game.data, "Press_AB")
end

-- ---------------------------------------------------------------------------
-- A SPIN
-- ---------------------------------------------------------------------------

function Gen3Roulette:coins()
  return math.max(0, math.floor(tonumber(self.game.save.coins) or 0))
end

function Gen3Roulette:spin()
  if self.stage ~= "bet" then return end
  if self:coins() < self.stake then
    self.message = Strings("You don't have enough COINS.")
    return
  end
  -- a bet with nothing left standing under it is not a bet
  if self:coverage(self.cursor) <= 0 then
    self.message = Strings("Nothing is left there.")
    return
  end
  self.game.save.coins = self:coins() - self.stake
  self.bet = { kind = self.cursor.kind, row = self.cursor.row,
               column = self.cursor.column }
  self.multiplierAtBet = self:multiplier(self.bet)
  self.stage = "spin"
  self.frame = 0
  self.message = nil
  -- WHICH SQUARE, rolled once and then shown: the wheel below is for
  -- watching, and a wheel that decided the answer by where it happened to
  -- stop would be a different game from the cartridge's.
  local board = self.cfg.board or {}
  self.landed = board[self.rng(1, #board)]
  Sound.play(self.game.data, "Press_AB")
end

function Gen3Roulette:settle()
  local landed = self.landed
  self.payout = 0
  if landed then
    local hit = (self.bet.kind == "square"
                 and landed.row == self.bet.row
                 and landed.column == self.bet.column)
                or (self.bet.kind == "row" and landed.row == self.bet.row)
                or (self.bet.kind == "column"
                    and landed.column == self.bet.column)
    -- the square has to have been STANDING for the bet to pay: one already
    -- struck off is a dead square the ball may still fall into
    if hit and self.standing[landed.id] then
      self.payout = self.stake * self.multiplierAtBet
      self.game.save.coins = math.min(9999, self:coins() + self.payout)
      self.message = Strings("%d COINS won!", self.payout)
      Sound.play(self.game.data, "Fanfare_ObtainedItem")
    else
      self.message = Strings("Nothing.")
    end
    -- ...and it comes off the board either way, which is what makes the next
    -- bet on that row worth more
    self.standing[landed.id] = nil
  end
  self.stage = "settle"
  self.frame = 0
end

function Gen3Roulette:boardEmpty()
  for _, sq in ipairs(self.cfg.board or {}) do
    if self.standing[sq.id] then return false end
  end
  return true
end

function Gen3Roulette:update()
  self.frame = (self.frame or 0) + 1
  local input = self.game.input

  if self.stage == "spin" then
    self.angle = (self.angle + 6) % 360
    if self.frame >= Gen3Roulette.SPIN_FRAMES then return self:settle() end
    return
  end

  if self.stage == "settle" then
    if self.frame >= Gen3Roulette.SETTLE_FRAMES
       and input and (input:wasPressed("a") or input:wasPressed("b")) then
      if self:boardEmpty() then
        -- every square struck off ends the sitting, which is the only way
        -- the board can be put back
        return leave(self)
      end
      self.stage = "bet"
      self.frame = 0
      self.message = nil
      self.landed = nil
    end
    return
  end

  if not input then return end
  if input:wasPressed("left") then return self:moveCursor(-1, 0) end
  if input:wasPressed("right") then return self:moveCursor(1, 0) end
  if input:wasPressed("up") then return self:moveCursor(0, -1) end
  if input:wasPressed("down") then return self:moveCursor(0, 1) end
  if input:wasPressed("a") then return self:spin() end
  if input:wasPressed("b") then return leave(self) end
end

function Gen3Roulette:keypressed(key)
  if key == "b" and self.stage == "bet" then return leave(self) end
end

-- ---------------------------------------------------------------------------
-- DRAWING
-- ---------------------------------------------------------------------------

local function cellRect(row, column)
  return BOARD_X + column * CELL_W, BOARD_Y + row * CELL_H, CELL_W - 2,
         CELL_H - 2
end

function Gen3Roulette:draw()
  love.graphics.setColor(0.12, 0.16, 0.30, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)

  -- the wheel, which is for watching
  local cx, cy, r = 30, 84, 24
  love.graphics.setColor(0.28, 0.20, 0.16, 1)
  love.graphics.circle("fill", cx, cy, r)
  love.graphics.setColor(0.80, 0.72, 0.55, 1)
  love.graphics.circle("line", cx, cy, r)
  local steps = Gen3Roulette.WHEEL_STEPS
  for i = 0, steps - 1 do
    local a = (self.angle + i * 360 / steps) * math.pi / 180
    local lit = (i % 2 == 1)
    love.graphics.setColor(lit and 0.95 or 0.45, lit and 0.85 or 0.40,
                           lit and 0.35 or 0.38, 1)
    love.graphics.circle("fill", cx + math.sin(a) * (r - 5),
                         cy - math.cos(a) * (r - 5), 2)
  end

  -- the column headers
  for c = 0, self.columns - 1 do
    local x, y = BOARD_X + c * CELL_W, BOARD_Y - HEAD_H - 2
    love.graphics.setColor(0.22, 0.30, 0.48, 1)
    love.graphics.rectangle("fill", x, y, CELL_W - 2, HEAD_H)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(("x%d"):format(self:multiplier({ kind = "column", row = 0,
                                               column = c })), x + 6, y + 4)
  end
  -- ...and the row headers
  for row = 0, self.rows - 1 do
    local x, y = BOARD_X - HEAD_W - 2, BOARD_Y + row * CELL_H
    love.graphics.setColor(0.22, 0.30, 0.48, 1)
    love.graphics.rectangle("fill", x, y, HEAD_W, CELL_H - 2)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(("x%d"):format(self:multiplier({ kind = "row", row = row,
                                               column = 0 })), x + 3, y + 5)
  end

  -- the twelve squares
  for row = 0, self.rows - 1 do
    for c = 0, self.columns - 1 do
      local sq = self:squareAt(row, c)
      local x, y, w, h = cellRect(row, c)
      local up = sq and self.standing[sq.id]
      love.graphics.setColor(up and 0.90 or 0.30, up and 0.88 or 0.30,
                             up and 0.80 or 0.32, 1)
      love.graphics.rectangle("fill", x, y, w, h)
      if sq then
        love.graphics.setColor(0, 0, 0, 1)
        Font.draw(tostring(sq.id), x + 4, y + 5)
      end
      if self.landed and sq and self.landed.id == sq.id
         and self.stage == "settle" then
        love.graphics.setColor(1, 0.85, 0.25, 1)
        love.graphics.rectangle("line", x - 1, y - 1, w + 2, h + 2)
      end
    end
  end

  -- the cursor
  do
    local c = self.cursor
    local x, y, w, h
    if c.kind == "square" then
      x, y, w, h = cellRect(c.row, c.column)
    elseif c.kind == "column" then
      x, y = BOARD_X + c.column * CELL_W, BOARD_Y - HEAD_H - 2
      w, h = CELL_W - 2, HEAD_H
    else
      x, y = BOARD_X - HEAD_W - 2, BOARD_Y + c.row * CELL_H
      w, h = HEAD_W, CELL_H - 2
    end
    if self.stage == "bet" and math.floor(self.frame / 8) % 2 == 0 then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("line", x - 2, y - 2, w + 4, h + 4)
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 0, 30, 3)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("COINS %d", self:coins()), 8, 6)
  local stake = Strings("BET %d  x%d", self.stake,
                        self:multiplier(self.cursor))
  Font.draw(stake, GBA_W - 8 - Font.width(stake), 6)

  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 16, 30, 4)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(self.message or Strings("Pick a square, a row or a column."),
            8, 138)
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3Roulette
