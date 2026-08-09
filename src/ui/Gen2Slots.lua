-- The Gold/Silver Game Corner slot machine (`special SlotMachine`, the
-- _SlotMachine loop in bank $24).  The cabinet, the six reel icons, the three
-- reel strips and the payout table are all ripped from the ROM into
-- field.gen2Slots; only the loop is rebuilt here.
--
-- Reels stop on A in order.  A reel that has passed its bias check nudges
-- itself toward a line (Slots_InitBias / the ReelAction_* jumptable), which is
-- what makes a "lucky" machine feel lucky; everything else is a straight stop
-- at the next centred icon.
--
-- Gen 2 is a Game Boy Color game, so the zones this screen hands PaletteFX
-- are the ROM's own SlotsPalettes -- the reels come out in GBC colour in every
-- COLORS mode, ADVANCED included, rather than the DMG greys the sheets decode
-- to.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")

local Gen2Slots = {}
Gen2Slots.__index = Gen2Slots
Gen2Slots.isOpaque = true

-- reel icon screen x and the window's vertical clip, read off SlotsTilemap:
-- each reel is `divider, white, white, divider` at columns 4-7 / 8-11 / 12-15
-- with the window spanning rows 4-9.
local SYM_X = { 40, 72, 104 }
local WIN_TOP, WIN_BOT = 32, 80
local STEP_FRAMES = 2

-- Paylines by bet, as offsets from the bottom of each window.  One coin buys
-- the middle row, two adds the top and bottom, three adds both diagonals.
local LINES = {
  { 1, 1, 1, bet = 1 },
  { 2, 2, 2, bet = 2 },
  { 0, 0, 0, bet = 2 },
  { 0, 1, 2, bet = 3 },
  { 2, 1, 0, bet = 3 },
}

local function slots(game)
  return game.data.field and game.data.field.gen2Slots or nil
end

local function coins(self)
  local save = self.game.save
  if save.g2Coins and not save.coins then save.coins = save.g2Coins end
  return save.coins or 0
end

function Gen2Slots.new(game, lucky)
  local self = setmetatable({}, Gen2Slots)
  self.game = game
  self.cfg = slots(game) or {}
  self.reels = self.cfg.reels or { {}, {}, {} }
  -- wReelPosition counts in half-icon steps like the ROM's OAM update, so an
  -- even offset shows three whole icons
  self.offset = { 0, 0, 0 }
  self.stopped = { false, false, false }
  self.bet = 3
  self.betIndex = 0
  self.yesno = 1
  self.frame = 0
  self.payout = 0
  self.stage = "bet"
  self.message = nil
  -- Slots_InitBias: one machine per visit rolls a friendlier bias
  self.bias = lucky and 3 or 1
  return self
end

-- ---------------------------------------------------------------------------
-- colour
-- ---------------------------------------------------------------------------

-- SlotMachinePals: BG 0-7 then OBJ 0-7, as the ROM's own CGB colours.  The
-- cabinet and the dialogue box take BG 6 and BG 7; a reel icon takes the OBJ
-- palette its own index names (Slots_UpdateReelPositionAndOAM builds the OAM
-- attribute by shifting the tile id right twice).
function Gen2Slots:sgbPalettes()
  local P = require("src.render.PaletteFX")
  local pals = self.cfg.palettes
  if not pals then return nil end
  local function bg(index) return pals[index + 1] end
  local function obj(index) return pals[index + 9] end
  local zones = { P.zone(bg(6), 0, 0, 19, 11), P.zone(bg(7), 0, 12, 19, 17) }
  -- one 16x16 zone per visible icon cell, so each reel symbol wears its own
  -- colour the way its sprite does on hardware
  for reel = 1, 3 do
    local column = SYM_X[reel] / 8
    for row = 0, 2 do
      local icon = self:iconAt(reel, 2 - row)
      if icon then
        zones[#zones + 1] = P.zone(obj(icon) or bg(6), column, 4 + row * 2,
                                   column + 1, 5 + row * 2)
      end
    end
  end
  return zones
end

-- ---------------------------------------------------------------------------
-- reels
-- ---------------------------------------------------------------------------

-- the icon `slot` rows up from the bottom of reel `reel`'s window at the
-- current (centred) offset; nil while the reel is mid-step
function Gen2Slots:iconAt(reel, slot)
  local strip = self.reels[reel]
  if not strip or #strip == 0 then return nil end
  if self.offset[reel] % 2 ~= 0 then return nil end
  local base = math.floor(self.offset[reel] / 2)
  return strip[((base + slot) % #strip) + 1]
end

function Gen2Slots:spinning()
  return not (self.stopped[1] and self.stopped[2] and self.stopped[3])
end

-- Slots_StopReel lands on the next centred icon; the bias lets a reel keep
-- rolling for up to `bias` more icons if that completes a line.
function Gen2Slots:stopReel(reel)
  if self.stopped[reel] then return end
  local strip = self.reels[reel]
  local best = 0
  for extra = 0, (#strip > 0 and self.bias or 0) do
    local probe = {}
    for other = 1, 3 do probe[other] = self.offset[other] end
    probe[reel] = probe[reel] + (probe[reel] % 2) + extra * 2
    local win = self:evaluate(probe, reel)
    if win > best then best = win self.stopAdjust = extra end
  end
  local extra = best > 0 and (self.stopAdjust or 0) or 0
  self.offset[reel] = self.offset[reel] + (self.offset[reel] % 2) + extra * 2
  self.stopped[reel] = true
  self.stopAdjust = nil
  Sound.play(self.game.data, "Sfx_StopSlot")
end

-- highest payout the given offsets pay, counting only reels already stopped
-- plus `upTo` (so a mid-spin probe cannot claim a line it has not settled)
function Gen2Slots:evaluate(offsets, upTo)
  local function iconOf(reel, slot)
    local strip = self.reels[reel]
    if not strip or #strip == 0 then return nil end
    if not (self.stopped[reel] or reel == upTo) then return nil end
    return strip[((math.floor(offsets[reel] / 2) + slot) % #strip) + 1]
  end
  local best = 0
  for _, line in ipairs(LINES) do
    if self.bet >= line.bet then
      local a, b, c = iconOf(1, line[1]), iconOf(2, line[2]), iconOf(3, line[3])
      if a and a == b and b == c then
        best = math.max(best, (self.cfg.payouts or {})[a] or 0)
      end
    end
  end
  return best
end

function Gen2Slots:settle()
  local won = self:evaluate(self.offset)
  local t = self.game.data.text or {}
  self.payout = won
  if won > 0 then
    self.game.save.coins = math.min(9999, coins(self) + won)
    self.message = (t._SlotsLinedUpText or Strings("lined up!\nWon {RAM:wStringBuffer2} coins!"))
      :gsub("{RAM:wStringBuffer2}", tostring(won))
    Sound.play(self.game.data, "Sfx_GetCoinFromSlots")
  else
    self.message = t._SlotsDarnText or Strings("Darn!")
  end
  self.stage = "result"
end

-- ---------------------------------------------------------------------------
-- loop
-- ---------------------------------------------------------------------------

function Gen2Slots:update()
  local input = self.game.input
  self.frame = self.frame + 1
  local t = self.game.data.text or {}

  if self.stage == "bet" then
    if input:wasPressed("up") then self.betIndex = math.max(0, self.betIndex - 1) end
    if input:wasPressed("down") then self.betIndex = math.min(2, self.betIndex + 1) end
    if input:wasPressed("b") then return self.game.stack:pop() end
    if input:wasPressed("a") then
      self.bet = 3 - self.betIndex
      if coins(self) < self.bet then
        self.message = t._SlotsNotEnoughCoinsText or Strings("Not enough\ncoins.")
        self.stage = "result"
        self.payout = 0
        return
      end
      self.game.save.coins = coins(self) - self.bet
      self.stopped = { false, false, false }
      self.payout = 0
      self.message = nil
      self.stage = "spin"
      Sound.play(self.game.data, "Sfx_SlotMachineStart")
    end
    return
  end

  if self.stage == "spin" then
    if self.frame % STEP_FRAMES == 0 then
      for reel = 1, 3 do
        if not self.stopped[reel] then
          self.offset[reel] = (self.offset[reel] + 1) % (#self.reels[reel] * 2)
        end
      end
    end
    if input:wasPressed("a") then
      for reel = 1, 3 do
        if not self.stopped[reel] then
          self:stopReel(reel)
          break
        end
      end
      if not self:spinning() then self:settle() end
    end
    return
  end

  if self.stage == "result" then
    if input:wasPressed("a") or input:wasPressed("b") then
      if coins(self) == 0 then
        self.message = t._SlotsRanOutOfCoinsText
          or Strings("Darn… Ran out of\ncoins…")
        self.stage = "broke"
        return
      end
      self.stage = "again"
      self.yesno = 1
    end
    return
  end

  if self.stage == "broke" then
    if input:wasPressed("a") or input:wasPressed("b") then
      self.game.stack:pop()
    end
    return
  end

  if self.stage == "again" then
    if input:wasPressed("up") or input:wasPressed("down") then
      self.yesno = self.yesno == 1 and 2 or 1
    elseif input:wasPressed("a") then
      if self.yesno == 1 then
        self.stage = "bet"
        self.message = nil
      else
        self.game.stack:pop()
      end
    elseif input:wasPressed("b") then
      self.game.stack:pop()
    end
  end
end

-- ---------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------

function Gen2Slots:loadArt()
  if self.artLoaded then return end
  self.artLoaded = true
  if self.cfg.bg then
    local ok, img = pcall(love.graphics.newImage, self.cfg.bg)
    self.bgImg = ok and img or nil
  end
  if self.cfg.symbols then
    local ok, img = pcall(love.graphics.newImage, self.cfg.symbols)
    self.iconImg = ok and img or nil
  end
  self.quads = {}
end

function Gen2Slots:drawCabinet()
  local map, width = self.cfg.tilemap, self.cfg.tilemapWidth or 20
  if not (self.bgImg and map) then return end
  local iw, ih = self.bgImg:getDimensions()
  for index = 1, #map do
    local id = map[index]
    local quad = self.quads[id]
    if not quad then
      quad = love.graphics.newQuad(id % 16 * 8, math.floor(id / 16) * 8,
                                   8, 8, iw, ih)
      self.quads[id] = quad
    end
    love.graphics.draw(self.bgImg, quad,
      (index - 1) % width * 8, math.floor((index - 1) / width) * 8)
  end
end

function Gen2Slots:drawReels()
  if not self.iconImg then return end
  local iw, ih = self.iconImg:getDimensions()
  for reel = 1, 3 do
    local strip = self.reels[reel]
    if strip and #strip > 0 then
      local x = SYM_X[reel]
      local step = self.offset[reel]
      local base = math.floor(step / 2)
      -- the strip scrolls in 8px half-icon steps; draw one icon past each
      -- edge so a mid-step window is never short a row
      for slot = -1, 3 do
        local top = WIN_BOT - 16 - slot * 16 + step % 2 * 8
        local clipTop = math.max(top, WIN_TOP)
        local clipBot = math.min(top + 16, WIN_BOT)
        if clipBot > clipTop then
          local icon = strip[((base + slot) % #strip) + 1]
          love.graphics.draw(self.iconImg,
            love.graphics.newQuad(icon * 16, clipTop - top,
                                  16, clipBot - clipTop, iw, ih),
            x, clipTop)
        end
      end
    end
  end
end

function Gen2Slots:drawBottom()
  local t = self.game.data.text or {}
  local text
  if self.stage == "bet" then
    text = t._SlotsBetHowManyCoinsText or Strings("Bet how many\ncoins?")
  elseif self.stage == "spin" then
    text = t._SlotsStartText or Strings("Start!")
  elseif self.stage == "again" then
    text = t._SlotsPlayAgainText or Strings("Play again?")
  else
    text = self.message
  end
  if not text then return end

  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  local row = 0
  for line in (text:gsub("\012", "\n") .. "\n"):gmatch("(.-)\n") do
    if row < 3 then Font.draw(line, 8, (14 + row * 2) * 8) end
    row = row + 1
  end

  if self.stage == "bet" then
    Font.drawBox(14, 12, 6, 5)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw("3", 17 * 8, 13 * 8)
    Font.draw("2", 17 * 8, 14 * 8)
    Font.draw("1", 17 * 8, 15 * 8)
    Font.drawCode(0xED, 16 * 8, (13 + self.betIndex) * 8)
  elseif self.stage == "again" then
    Font.drawBox(14, 12, 6, 4)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings("YES"), 16 * 8, 13 * 8)
    Font.draw(Strings("NO"), 16 * 8, 14 * 8)
    Font.drawCode(0xED, 15 * 8, (13 + (self.yesno == 1 and 0 or 1)) * 8)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Gen2Slots:draw()
  self:loadArt()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  self:drawCabinet()
  self:drawReels()

  -- SlotsLoop.PrintCoinsAndPayout prints both counters on row 1, under the
  -- CREDIT and PAYOUT labels the cabinet's top row draws
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(("%04d"):format(math.min(9999, coins(self))), 40, 8)
  Font.draw(("%04d"):format(self.payout or 0), 88, 8)
  love.graphics.setColor(1, 1, 1, 1)

  self:drawBottom()
end

return Gen2Slots
