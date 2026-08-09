-- Celadon's Card Flip (`special CardFlip`, the _CardFlip loop in bank $38).
--
-- The board, the face-down and face-up card stamps, the per-card tile pair,
-- the nine palettes and the cursor's six OAM templates are all ripped from the
-- ROM into field.gen2CardFlip; only the loop is rebuilt here.
--
-- Three coins a play, twelve plays to a 24-card deck.  Each play deals two
-- face-down cards, the player stops the alternation on one of them, then bets
-- on a square of the 6x8 grid: an exact card pays 72, a single number 18, a
-- single Pokemon 12, a pair of numbers 9, a pair of Pokemon 6.
--
-- Gen 2 is a Game Boy Color game, so the zones this screen hands PaletteFX are
-- the ROM's own CardFlip_InitAttrPals palettes: the board comes out in GBC
-- colour in every COLORS mode, ADVANCED included, rather than the DMG greys
-- the sheets decode to.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")

local Gen2CardFlip = {}
Gen2CardFlip.__index = Gen2CardFlip
Gen2CardFlip.isOpaque = true

local BOARD_COL = 9          -- CardFlip_InitTilemap copies to tilemap offset 9
local GREEN = 0x29           -- CardFlip_FillGreenBox
local BET = 3
local FLIP_FRAMES = 4        -- .ChooseACard toggles every four frames

-- CardFlip_DisplayCardBack's stamp, 5 columns by 6 rows at 38:$4BE6.  The
-- face-up stamp lives in field.gen2CardFlip.faceUp.
local CARD_BACK = {
  0x08, 0x09, 0x09, 0x09, 0x0a,
  0x0b, 0x28, 0x2b, 0x28, 0x0c,
  0x0b, 0x2c, 0x2d, 0x2e, 0x0c,
  0x0b, 0x2f, 0x30, 0x31, 0x0c,
  0x0b, 0x32, 0x33, 0x34, 0x0c,
  0x0d, 0x0e, 0x0e, 0x0e, 0x0f,
}
local CARD_AT = { { 2, 0 }, { 2, 6 } }   -- $c3a2 and $c41a

-- CardFlip_BlankDiscardedCardSlot: the two numbers of a pair share one
-- three-tile block, so which tiles a discard leaves behind depends on whether
-- its partner has gone too.
local BLANK_UPPER = { 0x37, 0x38, 0x39 }
local BLANK_LOWER = { 0x3b, 0x3c, 0x3c }
local BLANK_BOTH = 0x3d
local BLANK_TOP, BLANK_TAIL = 0x36, 0x3a

local function cfg(game)
  return game.data.field and game.data.field.gen2CardFlip or nil
end

local function coins(self)
  local save = self.game.save
  if save.g2Coins and not save.coins then save.coins = save.g2Coins end
  return save.coins or 0
end

-- CardFlip_ShuffleDeck drops values 23..1 into random free slots and leaves
-- whatever slot is still empty holding 0.
local function shuffle()
  local deck = {}
  for at = 1, 24 do deck[at] = 0 end
  for value = 23, 1, -1 do
    local at
    repeat at = love.math.random(24) until deck[at] == 0
    deck[at] = value
  end
  return deck
end

function Gen2CardFlip.new(game)
  local self = setmetatable({}, Gen2CardFlip)
  self.game = game
  self.cfg = cfg(game) or {}
  self.deck = shuffle()
  self.discarded = {}
  self.played = 0
  self.whichCard = 0
  self.faceUpCard = nil
  self.cursor = 2 * 6 + 2      -- the first single-card square
  self.frame = 0
  self.stage = "ask"
  self.yesno = 1
  self.message = (game.data.text or {})._CardFlipPlayWithThreeCoinsText
    or Strings("Play with three\ncoins?")
  return self
end

local function text(self, key, fallback)
  return (self.game.data.text or {})[key] or Strings(fallback)
end

-- ---------------------------------------------------------------------------
-- colour
-- ---------------------------------------------------------------------------

-- CardFlip_InitAttrPals: palette 0 everywhere, palette 1 down the twelve
-- play-counter lights, and palettes 1-4 on the four Pokemon headers.  A card
-- turned face up takes its own Pokemon's palette.
function Gen2CardFlip:sgbPalettes()
  local P = require("src.render.PaletteFX")
  local pals = self.cfg.palettes
  if not pals then return nil end
  local function bg(index) return pals[index + 1] end
  local zones = { P.zone(bg(0), 0, 0, 19, 17), P.zone(bg(1), BOARD_COL, 0, BOARD_COL, 11) }
  for mon = 0, 3 do
    local column = BOARD_COL + 3 + mon * 2
    zones[#zones + 1] = P.zone(bg(mon + 1), column, 1, column + 1, 2)
  end
  if self.faceUpCard then
    local at = CARD_AT[self.whichCard + 1]
    zones[#zones + 1] = P.zone(bg(self.faceUpCard % 4 + 1),
                               at[1], at[2], at[1] + 4, at[2] + 5)
  end
  -- Every cursor sprite carries OAM attribute bit 7, so on hardware the solid
  -- red block only shows through the board's colour-0 gaps: what the player
  -- sees is a red frame around the square.  PaletteFX cannot express
  -- BG-over-OBJ priority, so the frame is drawn true-colour and its four
  -- strips opt out of the shade remap.
  if self.stage == "bet" then
    for _, strip in ipairs(self:cursorFrame()) do
      zones[#zones + 1] = { colors = false, x = strip[1], y = strip[2],
                            w = strip[3], h = strip[4] }
    end
  end
  return zones
end

-- the four 1px strips of the cursor frame, clipped to the screen
function Gen2CardFlip:cursorFrame()
  local sprites = self:cursorSprites()
  if #sprites == 0 then return {} end
  local x0, y0, x1, y1 = 160, 144, 0, 0
  for _, sprite in ipairs(sprites) do
    x0, y0 = math.min(x0, sprite.x), math.min(y0, sprite.y)
    x1, y1 = math.max(x1, sprite.x + 8), math.max(y1, sprite.y + 8)
  end
  x0, y0 = math.max(0, x0), math.max(0, y0)
  x1, y1 = math.min(160, x1), math.min(144, y1)
  local w, h = x1 - x0, y1 - y0
  if w <= 0 or h <= 0 then return {} end
  return {
    { x0, y0, w, 1 }, { x0, y1 - 1, w, 1 },
    { x0, y0, 1, h }, { x1 - 1, y0, 1, h },
  }
end

-- CardFlip_CopyOAM: db count, then count x (y, x, tile, attr) offsets from the
-- square's base position in OAMData, with the usual OAM -8/-16 screen bias.
function Gen2CardFlip:cursorSprites()
  local slots, shapes = self.cfg.slots, self.cfg.shapes
  local slot = slots and slots[self.cursor + 1]
  local sprites = slot and shapes and shapes[slot.shape]
  if not sprites then return {} end
  local out = {}
  for index, sprite in ipairs(sprites) do
    out[index] = {
      x = (slot.x + sprite.x) % 256 - 8,
      y = (slot.y + sprite.y) % 256 - 16,
      tile = sprite.tile,
      flipX = math.floor(sprite.attr / 32) % 2 == 1,
      flipY = math.floor(sprite.attr / 64) % 2 == 1,
    }
  end
  return out
end

-- ---------------------------------------------------------------------------
-- bets
-- ---------------------------------------------------------------------------

-- CardFlip_CheckWinCondition's jumptable, one entry per cursor square: the
-- payouts are the fair multiples of the three-coin stake over 24 cards.
function Gen2CardFlip:betAt(slot)
  local row, col = math.floor(slot / 6), slot % 6
  if row < 2 then
    if col < 2 then return { pay = 0 } end
    if row == 0 then return { pay = 6, monPair = col < 4 and 0 or 1 } end
    return { pay = 12, mon = col - 2 }
  end
  if col == 0 then return { pay = 9, numPair = math.floor((row - 2) / 2) } end
  if col == 1 then return { pay = 18, num = row - 2 } end
  return { pay = 72, mon = col - 2, num = row - 2 }
end

function Gen2CardFlip:payout()
  local card = self.faceUpCard
  if not card then return 0 end
  local mon, num = card % 4, math.floor(card / 4)
  local bet = self:betAt(self.cursor)
  if bet.pay == 0 then return 0 end
  if bet.monPair then return math.floor(mon / 2) == bet.monPair and bet.pay or 0 end
  if bet.numPair then return math.floor(num / 2) == bet.numPair and bet.pay or 0 end
  if bet.mon and bet.num then
    return (mon == bet.mon and num == bet.num) and bet.pay or 0
  end
  if bet.mon then return mon == bet.mon and bet.pay or 0 end
  return num == bet.num and bet.pay or 0
end

-- ---------------------------------------------------------------------------
-- loop
-- ---------------------------------------------------------------------------

function Gen2CardFlip:deal()
  self.faceUpCard = nil
  self.whichCard = 0
  self.stage = "choose"
  self.message = text(self, "_CardFlipChooseACardText", "Choose a card.")
end

function Gen2CardFlip:update()
  local input = self.game.input
  self.frame = self.frame + 1

  if self.stage == "ask" or self.stage == "again" then
    if input:wasPressed("up") or input:wasPressed("down") then
      self.yesno = self.yesno == 1 and 2 or 1
    elseif input:wasPressed("b") then
      self.game.stack:pop()
    elseif input:wasPressed("a") then
      if self.yesno ~= 1 then return self.game.stack:pop() end
      if coins(self) < BET then
        self.message = text(self, "_CardFlipNotEnoughCoinsText", "Not enough coins…")
        self.stage = "broke"
        return
      end
      self.game.save.coins = coins(self) - BET
      self:deal()
    end
    return
  end

  if self.stage == "broke" then
    if input:wasPressed("a") or input:wasPressed("b") then self.game.stack:pop() end
    return
  end

  if self.stage == "choose" then
    if self.frame % FLIP_FRAMES == 0 then
      self.whichCard = 1 - self.whichCard
    end
    if input:wasPressed("a") then
      Sound.play(self.game.data, "Sfx_StopSlot")
      self.stage = "bet"
      self.message = text(self, "_CardFlipPlaceYourBetText", "Place your bet.")
    end
    return
  end

  if self.stage == "bet" then
    local row, col = math.floor(self.cursor / 6), self.cursor % 6
    if input:wasPressed("up") then row = (row - 1) % 8 end
    if input:wasPressed("down") then row = (row + 1) % 8 end
    if input:wasPressed("left") then col = (col - 1) % 6 end
    if input:wasPressed("right") then col = (col + 1) % 6 end
    self.cursor = row * 6 + col
    if input:wasPressed("a") then self:reveal() end
    return
  end

  if self.stage == "reveal" then
    if input:wasPressed("a") or input:wasPressed("b") then
      self.played = self.played + 1
      if self.played >= 12 then
        self.deck = shuffle()
        self.discarded = {}
        self.played = 0
        self.message = text(self, "_CardFlipShuffledText", "The cards have\nbeen shuffled.")
        self.stage = "shuffled"
        return
      end
      self.stage = "again"
      self.yesno = 1
      self.message = text(self, "_CardFlipPlayAgainText", "Want to play\nagain?")
    end
    return
  end

  if self.stage == "shuffled" then
    if input:wasPressed("a") or input:wasPressed("b") then
      self.stage = "again"
      self.yesno = 1
      self.message = text(self, "_CardFlipPlayAgainText", "Want to play\nagain?")
    end
  end
end

-- .CheckTheCard: each play burns two deck slots and discards whichever of the
-- pair the player stopped on.
function Gen2CardFlip:reveal()
  local card = self.deck[self.played * 2 + self.whichCard + 1] or 0
  self.faceUpCard = card
  self.discarded[card] = true
  local won = self:payout()
  self.won = won
  if won > 0 then
    self.game.save.coins = math.min(9999, coins(self) + won)
    self.message = text(self, "_CardFlipYeahText", "Yeah!")
    Sound.play(self.game.data, "Sfx_GetCoinFromSlots")
  else
    self.message = text(self, "_CardFlipDarnText", "Darn…")
  end
  self.stage = "reveal"
end

-- ---------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------

function Gen2CardFlip:loadArt()
  if self.artLoaded then return end
  self.artLoaded = true
  self.quads = {}
  if self.cfg.bg then
    local ok, img = pcall(love.graphics.newImage, self.cfg.bg)
    self.bgImg = ok and img or nil
  end
  if self.cfg.cursor then
    local ok, img = pcall(love.graphics.newImage, self.cfg.cursor)
    self.cursorImg = ok and img or nil
  end
end

function Gen2CardFlip:tile(id, tx, ty)
  if not self.bgImg then return end
  local quad = self.quads[id]
  if not quad then
    local iw, ih = self.bgImg:getDimensions()
    quad = love.graphics.newQuad(id % 16 * 8, math.floor(id / 16) * 8, 8, 8, iw, ih)
    self.quads[id] = quad
  end
  love.graphics.draw(self.bgImg, quad, tx * 8, ty * 8)
end

function Gen2CardFlip:stamp(map, width, tx, ty)
  for index = 1, #map do
    self:tile(map[index], tx + (index - 1) % width, ty + math.floor((index - 1) / width))
  end
end

function Gen2CardFlip:drawBoard()
  local map, width = self.cfg.tilemap, self.cfg.tilemapWidth or 11
  if not map then return end
  self:stamp(map, width, BOARD_COL, 0)

  -- the twelve play-counter lights down the board's left edge
  for row = 0, 11 do
    if row < self.played then self:tile(0xf5, BOARD_COL, row) end
  end

  for mon = 0, 3 do
    local column = BOARD_COL + 4 + mon * 2
    for pair = 0, 2 do
      local top = 3 + pair * 3
      local upper = self.discarded[(pair * 2) * 4 + mon]
      local lower = self.discarded[(pair * 2 + 1) * 4 + mon]
      if upper then
        self:tile(BLANK_TOP, column, top)
        self:tile(lower and BLANK_BOTH or BLANK_UPPER[pair + 1], column, top + 1)
      end
      if lower then
        self:tile(upper and BLANK_BOTH or BLANK_LOWER[pair + 1], column, top + 1)
        self:tile(BLANK_TAIL, column, top + 2)
      end
    end
  end
end

function Gen2CardFlip:drawCards()
  if self.stage == "ask" or self.stage == "again"
    or self.stage == "broke" or self.stage == "shuffled" then
    return
  end
  for index = 1, 2 do
    local at = CARD_AT[index]
    local chosen = index == self.whichCard + 1
    if self.stage ~= "choose" and not chosen then
      -- .ChooseACard green-boxes whichever card the player passed over
    elseif self.stage == "reveal" then
      self:stamp(self.cfg.faceUp or {}, self.cfg.faceUpWidth or 5, at[1], at[2])
      local card = self.cfg.cards and self.cfg.cards[self.faceUpCard]
      if card then
        -- the digit is a font tile ($F7 + number), not part of the card sheet
        love.graphics.setColor(0, 0, 0, 1)
        Font.draw(tostring(math.floor(self.faceUpCard / 4) + 1),
                  (at[1] + 3) * 8, (at[2] + 1) * 8)
        love.graphics.setColor(1, 1, 1, 1)
        for step = 0, 8 do
          self:tile(card.base + step, at[1] + 1 + step % 3, at[2] + 2 + math.floor(step / 3))
        end
      end
    else
      self:stamp(CARD_BACK, 5, at[1], at[2])
    end
  end
  if self.stage == "choose" then
    local at = CARD_AT[self.whichCard + 1]
    love.graphics.setColor(0, 0, 0, 1)
    Font.drawCode(0xED, (at[1] - 1) * 8, (at[2] + 2) * 8)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

-- CardFlip_InitAttrPals' ninth palette is the cursor's, and its third entry is
-- the red the frame is drawn in.
function Gen2CardFlip:drawCursor()
  local pals = self.cfg.palettes
  local red = pals and pals[9] and pals[9][3] or { 255, 0, 0 }
  love.graphics.setColor(red[1] / 255, red[2] / 255, red[3] / 255, 1)
  for _, strip in ipairs(self:cursorFrame()) do
    love.graphics.rectangle("fill", strip[1], strip[2], strip[3], strip[4])
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Gen2CardFlip:drawBottom()
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  local row = 0
  for line in ((self.message or "") .. "\n"):gmatch("(.-)\n") do
    if row < 2 then Font.draw(line, 8, (13 + row * 2) * 8) end
    row = row + 1
  end

  -- CardFlip_PrintCoinBalance: a nine-wide box at row 15, "COIN" then four
  -- leading-zero digits
  Font.drawBox(BOARD_COL, 15, 11, 3)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("COIN"), (BOARD_COL + 1) * 8, 16 * 8)
  Font.draw(("%04d"):format(math.min(9999, coins(self))), (BOARD_COL + 6) * 8, 16 * 8)

  if self.stage == "ask" or self.stage == "again" then
    Font.drawBox(14, 12, 6, 4)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings("YES"), 16 * 8, 13 * 8)
    Font.draw(Strings("NO"), 16 * 8, 14 * 8)
    Font.drawCode(0xED, 15 * 8, (13 + (self.yesno == 1 and 0 or 1)) * 8)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Gen2CardFlip:draw()
  self:loadArt()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  for row = 0, 17 do
    for col = 0, 19 do self:tile(GREEN, col, row) end
  end
  self:drawBoard()
  self:drawCards()
  if self.stage == "bet" then self:drawCursor() end
  self:drawBottom()
end

return Gen2CardFlip
