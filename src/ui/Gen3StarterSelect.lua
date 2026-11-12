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
--       labelX = { 0, 128, 64 },  labelY = { 72, 80, 32 },
--       handFrame = 4, ...
--     }
--
-- The two coordinate tables are NOT related to each other, which is the thing
-- to know before editing anything here: sPokeballCoords is in pixels and
-- sStarterLabelCoords, six bytes after it at 5B1DF2, is in TILES, and the
-- plate a Pokemon's name goes in can sit on the opposite side of the screen
-- from the ball it names -- Mudkip's ball is at x 180 and its plate at x 64.
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
local Gen3Wide = require("src.ui.Gen3Wide")

local Gen3StarterSelect = {}
Gen3StarterSelect.__index = Gen3StarterSelect

local GBA_W, GBA_H = 240, 160

-- RECONSTRUCTED: the ball nearest the hand rocks, on a slow cycle.  The three
-- frames the sheet carries are the whole animation the cartridge has for it.
local BOUNCE_PERIOD = 0.45

Gen3StarterSelect.holdsUIAnchors = true

-- THE ROUTE IS NOT BEHIND THIS SCREEN.
--
-- Reported from play, with a screenshot: "The starter selection menu doesnt
-- show in full screen".  It was drawing its 240x160 picture over a route that
-- went on drawing underneath and out to the edges of the display, so the bag
-- scene sat in a window of grass.
--
-- The cartridge does not overlay anything: ChooseStarter sets CB2_ChooseStarter
-- and Route 101 stops existing until the callback returns.  `isOpaque` is this
-- stack's word for that -- it stops the draw walking below this state -- and
-- every comparable full-screen Gen 3 screen already sets it, including
-- BirchSpeech, which is the scene immediately before this one.
Gen3StarterSelect.isOpaque = true

-- ...AND IT FILLS THE DISPLAY.  160 rows always, and as many columns as the
-- window's shape asks for (Gen3Wide), with the cartridge's own 240 centred in
-- them.  Without this, being opaque would only trade the grass for two black
-- bars.
function Gen3StarterSelect:uiSize() return Gen3Wide.uiSize() end

-- WHERE THE NAME PLATE GOES, in tiles, straight off sStarterLabelCoords.
--
-- The cartridge keeps this in a table of its own -- {0,9}, {16,10}, {8,4} at
-- 5B1DF2, six bytes after sPokeballCoords -- and those positions have nothing
-- to do with where the ball is: Mudkip's ball is at x 180 and its plate is at
-- x 64, over on the other side of the screen.  The plate was being centred on
-- the ball instead, which put it on top of the Pokemon it was naming.
--
-- Carried here as a fallback because the importer could not read the table
-- until now (it was looking for a second set of BALL coordinates and this is a
-- set of TILE coordinates), so every cache imported before that fix has no
-- answer to give.  A cache that does have one wins.
local LABEL_TILES = { { 0, 9 }, { 16, 10 }, { 8, 4 } }
-- sWindowTemplate_StarterLabel: 13 tiles by 4, and the text is centred in its
-- 104-pixel width rather than left-aligned
local LABEL_TW, LABEL_TH = 13, 4

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
    -- RUN MODES: a randomized-starters save shows the mon it will get
    id = require("src.runmodes.RunHooks").shownStarter(game, id)
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

-- The plate's top-left corner in pixels: the cache's if it has one, else the
-- cartridge's own table above.
function Gen3StarterSelect:labelAt(i)
  local r = self.record
  local lx = r.labelX and tonumber(r.labelX[i])
  local ly = r.labelY and tonumber(r.labelY[i])
  if lx and ly then return lx, ly end
  local tile = LABEL_TILES[i]
  if not tile then return nil, nil end
  return tile[1] * 8, tile[2] * 8
end

function Gen3StarterSelect:draw()
  love.graphics.setColor(1, 1, 1, 1)

  -- THE SURFACE, AND THE CARTRIDGE'S 240 COLUMNS INSIDE IT.  Everything below
  -- is written in the cartridge's own coordinates; the translate is the only
  -- thing that knows the screen is wider.
  local W = select(1, Gen3Wide.uiSize())
  local inset = Gen3Wide.inset(W)

  if self.bg and self.bgQuad then
    -- the margin, painted from the picture's own edge columns.  One pixel
    -- stretched sideways can only repeat a colour that is already the whole
    -- of that row, so this fills the slack rather than smearing anything --
    -- and outside the grass circle this art is a flat field, so it is exact.
    if inset > 0 then
      local bw, bh = self.bg:getDimensions()
      self.edgeL = self.edgeL or love.graphics.newQuad(0, 0, 1, math.min(GBA_H, bh), bw, bh)
      self.edgeR = self.edgeR or
        love.graphics.newQuad(math.min(GBA_W, bw) - 1, 0, 1, math.min(GBA_H, bh), bw, bh)
      love.graphics.draw(self.bg, self.edgeL, 0, 0, 0, inset, 1)
      love.graphics.draw(self.bg, self.edgeR, inset + GBA_W, 0, 0, inset + 1, 1)
    end
    love.graphics.draw(self.bg, self.bgQuad, inset, 0)
  end

  love.graphics.push()
  love.graphics.translate(inset, 0)

  local hw, hh = self.frameW / 2, self.frameH / 2
  local i = self.index
  local x, y = self:ballAt(i)
  local glyphH = Font.glyphHeight()
  local textInset = math.max(0, math.floor((16 - glyphH) / 2))

  -- WINDOWS FIRST, POKEMON SECOND, and that order is the cartridge's layering
  -- rather than a preference.  Every box on this screen is a BG0 window and
  -- the Pokemon is an OBJ sprite, so the sprite is ABOVE all three of them --
  -- which is why the cartridge can put Mudkip's name plate and its Yes/No box
  -- where the sprite will stand without hiding it.  Drawn the other way round,
  -- as this did, the boxes paint over the Pokemon.
  local confirming = self.stage == "confirm"
                     and (self.picGrow or 0) >= GROW_FRAMES

  -- THE PLATE BELONGS TO THE POINTING, NOT TO THE CHOOSING.
  --
  -- Reported from play: "the box showing the pokemons name is still covered
  -- have it appear in a way where its not covered and is visible when
  -- selecting a pokemon".  It was drawn in the confirm half, where a 64-pixel
  -- front sprite standing on the ball reaches down across it -- and putting
  -- the box back on top of the sprite is the complaint before last.
  --
  -- Neither is the cartridge, and the cartridge has no such collision to
  -- resolve, because the two are never on screen together.  The A-button
  -- handler opens `ClearStarterLabel();` and only then creates the circle and
  -- the Pokemon; the plate is put up by Task_StarterChoose when the screen
  -- opens, taken down by Task_MoveStarterChooseCursor and put up again for
  -- the new selection by Task_CreateStarterLabel.  It is what you read WHILE
  -- pointing, and pressing A is what replaces it with the Pokemon itself.
  --
  -- So it moves to the pick half, where nothing can cover it -- which is also
  -- exactly what was asked for.
  if self.stage ~= "confirm" then
    -- the name plate: sStarterLabelCoords, with the dex CATEGORY over the
    -- species name, each centred across the window's 13 tiles
    local lx, ly = self:labelAt(i)
    if lx and ly then
      local shown = require("src.runmodes.RunHooks").shownStarter(self.game, self.species[i])
      local def = self.game.data.pokemon and self.game.data.pokemon[shown]
      local name = (def and def.name) or tostring(shown)
      local rows = def and def.category and { def.category, name } or { name }
      local tx = math.floor(lx / 8) - 1
      local ty = math.floor(ly / 8) - 1
      -- the cartridge's frame bleeds four pixels past the window's left edge
      -- and Treecko's plate starts at column 0, so on a screen with no margin
      -- to bleed into the box is nudged back on instead of off
      if inset <= 0 then tx = math.max(0, tx) end
      ty = math.max(0, ty)
      Font.drawBox(tx, ty, LABEL_TW + 2, LABEL_TH + 2)
      love.graphics.setColor(0, 0, 0, 1)
      for n, row in ipairs(rows) do
        local rowX = (tx + 1) * 8
                     + math.max(0, math.floor((LABEL_TW * 8 - Font.width(row)) / 2))
        Font.draw(row, math.floor(rowX),
                  (ty + 1 + (n - 1) * 2) * 8 + textInset)
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  if confirming then
    -- the question (sWindowTemplates[0]: left 3, top 15, 24x4) ...
    local lines = self:confirmLines()
    Font.drawBox(2, 14, 26, 6)
    love.graphics.setColor(0, 0, 0, 1)
    for n, line in ipairs(lines) do
      Font.draw(line, 3 * 8, (15 + (n - 1) * 2) * 8 + textInset)
    end
    love.graphics.setColor(1, 1, 1, 1)

    -- ...and YES/NO (sWindowTemplate_ConfirmStarter: left 24, top 9, 5x4)
    local YES_TX, YES_TY = 23, 8
    Font.drawBox(YES_TX, YES_TY, 7, 6)
    love.graphics.setColor(0, 0, 0, 1)
    for n, label in ipairs({ Strings("YES"), Strings("NO") }) do
      local rowY = (YES_TY + 1 + (n - 1) * 2) * 8 + textInset
      Font.draw(label, (YES_TX + 2) * 8, rowY)
      if (self.yes and n == 1) or (not self.yes and n == 2) then
        Font.drawCode(Theme.cursor, (YES_TX + 1) * 8, rowY)
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- the balls, the chosen one bouncing
  for n = 1, #self.species do
    local bx, by = self:ballAt(n)
    local frame, lift = 1, 0
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

  -- THE PICTURE, and only once a ball has been pressed.  The cartridge
  -- creates the sprite in the A-button handler and at the ball's own
  -- coordinates (CreatePokemonFrontSprite(species, sPokeballCoords[sel][0],
  -- [1])), so before that there is nothing above the grass at all, and when
  -- there is, it grows out of the ball it is standing on.
  local pic = (self.stage == "confirm") and self.pics[i] or nil
  if pic then
    local pw, ph = pic:getDimensions()
    local grow = math.min(1, (self.picGrow or 0) / GROW_FRAMES)
    -- eased so it settles rather than stopping dead
    local scale = 0.25 + 0.75 * (1 - (1 - grow) * (1 - grow))
    love.graphics.draw(pic, math.floor(x), math.floor(y), 0, scale, scale,
                       pw / 2, ph / 2)
  end

  -- the hand, pointing down at the ball
  local quad = self.quads[self.handFrame]
  if quad then
    love.graphics.draw(self.sheet, quad,
                       math.floor(x - hw), math.floor(y - hh - self.frameH + 4))
  end

  love.graphics.pop()
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3StarterSelect
