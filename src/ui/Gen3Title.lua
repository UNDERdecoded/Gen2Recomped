-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Emerald's title screen.
--
-- Not a branch inside TitleState.  That screen is a Game Boy composition --
-- a logo tile block, a version ribbon, a cycling front sprite out of
-- TitleMons, a copyright row -- and Emerald has none of those things: it is
-- two scrolling background layers, Rayquaza in silhouette with a cloud field
-- drifting over him, and PRESS START.  Sharing one screen between them would
-- have meant a third layout mode inside a file that already carries three.
--
-- THE PICTURE IS THE CARTRIDGE'S.  Both layers come out of the ROM through
-- the scene stage, palettes and all, and are drawn here at the scale that
-- fits a Game Boy screen: the GBA's is 240x160 and this engine's is 160x144,
-- so the art is shown at two thirds and the band it leaves at the bottom
-- carries the wordmark and the prompt.  That band is the honest way round --
-- cropping to 160 wide would cut Rayquaza's own coils off both sides.
--
-- THE WORDMARK IS THE CARTRIDGE'S TOO, now.  It was not: the scene pass finds
-- TILED BACKGROUNDS, and neither half of Emerald's branding is one -- the
-- POKeMON logo is a 256-colour BITMAP whose tilemap is an identity ramp, and
-- EMERALD VERSION is an 8bpp SPRITE that never passes a background loader at
-- all.  Both are found and composed now (see the overlay pass in
-- RomExtractorGen3:extractScenes), so the words are the cartridge's pixels.
-- The font fallback below is what a dataset without them still gets.
--
-- WHAT IS STILL RECONSTRUCTED is where they sit.  A GBA sprite's position
-- comes out of OAM at run time, not out of the sheet, so the two offsets in
-- LOGO_Y / VERSION_Y are measured off the screen rather than derived, and
-- they are the numbers to correct against a screenshot.

local Font = require("src.render.Font")
local Gen3Scene = require("src.render.Gen3Scene")
local Gen3Wide = require("src.ui.Gen3Wide")
local Music = require("src.core.Music")
local Screens = require("src.ui.Screens")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")

local Gen3Title = {}
Gen3Title.__index = Gen3Title
Gen3Title.isOpaque = true

-- THE GBA SCREEN, ASKED FOR RATHER THAN SCALED INTO.
--
-- The first version of this drew Emerald's 240x160 title at two thirds inside
-- the Game Boy's 160x144 canvas, letterboxed, with the wordmark in the band it
-- left.  That was wrong twice over: the art resamples at 2/3, which is not a
-- thing pixel art survives, and the whole screen is Emerald's -- there is no
-- Game Boy composition here to preserve.  Renderer:setUISize already exists
-- for exactly this (the widescreen battle asks for 304x144), so this screen
-- asks for the surface the cartridge draws on and uses all of it.
local GBA_W, GBA_H = 240, 160

-- THE CLOUDS GO UP, NOT SIDEWAYS, AND THEY WOBBLE.
--
-- Reported from play: "in the main menu the clouds are supposed to scroll
-- upward and move with a wave like distortion not left to right".  They are,
-- and both halves of that are the cartridge's own, read off the title
-- screen's task (0AAD64) and the scanline effect it arms.
--
-- WHICH BACKGROUND IS WHICH.  Running the title's own callback chain through
-- the intro's THUMB interpreter (tools/gen3_intro_act3.py's Cpu, entered at
-- 0AA7A4 with SetMainCallback2 and CreateTask stubbed) gives the control
-- registers outright: BG0CNT 1A0B is Rayquaza (char block 2, map 26, priority
-- 3), BG1CNT 1B0E is the cloud field (char block 3, map 27, priority 2) and
-- BG2CNT 4981 is the 256-colour logo on an affine background in front of both.
-- So the clouds are BG1, and everything below is BG1's.
--
-- THE SCROLL.  Phase three's task does, every OTHER frame, data[4]++ and then
-- writes data[4] / 2 into gBattle_BG1_Y (02022E1A) -- which the title's VBlank
-- hands to BG1VOFS.  A rising VOFS walks the window DOWN the map, which shows
-- as the picture rising: a quarter of a pixel a frame, upward.
--
-- THE WAVE.  The init calls ScanlineEffect_InitWave(0, 160, frequency 4,
-- amplitude 4, delay 0, regOffset 4, battle offsets) -- regOffset 4 is
-- REG_BG0HOFS + 4, which is BG1HOFS, so it is a per-SCANLINE horizontal
-- offset.  The table it builds (0BA33C) is
--     wave[i] = (gSineTable[(i * frequency) & 0xFF] * amplitude) >> 8
-- so with those two arguments it is a sine four pixels either side whose
-- wavelength is 256/4 = 64 scanlines, and a delay interval of zero advances
-- its phase one entry every frame.  Nothing is added to it here: the same
-- task writes gBattle_BG1_X (02022E18), which the effect adds to every row,
-- as zero.
local CLOUD_PIXELS_PER_FRAME = 1 / 4   -- gBattle_BG1_Y, upward
local CLOUD_WAVE_AMPLITUDE = 4         -- pixels either side
local CLOUD_WAVE_ROWS = 64             -- 256 sine entries over frequency 4
local CLOUD_WAVE_ROWS_PER_FRAME = 1    -- delayInterval 0

-- One scanline's horizontal offset, which is the cartridge's own table read as
-- the sine it is: wave[i] = (gSineTable[i * 4] * 4) >> 8, and gSineTable is a
-- full turn in 256 entries scaled by 256.
local function cloudWave(row, phase)
  return math.floor(CLOUD_WAVE_AMPLITUDE
                    * math.sin((row + phase) / CLOUD_WAVE_ROWS * 2 * math.pi)
                    + 0.5)
end

-- RAYQUAZA'S MARKINGS, AND WHAT MAKES THEM APPEAR.
--
-- Reported from play: "Rayquaza is missing the yellow glow in our main menu as
-- well".  There was nothing to draw: the markings are already in the backdrop,
-- in a colour identical to the body they sit on, and the cartridge makes them
-- appear by rewriting that one palette entry.  Gen3Scene.animatedEntry finds
-- which entry that is from the data alone -- palette 14 holds 004A62 at index
-- 11 over the whole silhouette AND at index 15 over 1149 pixels inside it, and
-- a duplicate in a sixteen-colour palette is only worth a slot if something
-- rewrites it -- and maskImage gives those pixels as a stencil.
--
-- THE COLOUR AND THE RATE ARE NOT DERIVED.  The colour is measured off a
-- screenshot of the cartridge and snapped to the GBA's own five bits per
-- channel; the period is one cycle over 256 frames, which is what a routine
-- counting an eight-bit frame number through a cosine gives.  Both are numbers
-- to correct against a capture, like LOGO_Y below.
local GLOW = { 246 / 255, 246 / 255, 98 / 255 }
local GLOW_FRAMES = 256

-- MEASURED, not derived (see the note at the top of this file): where the
-- branding sits on the 240x160 screen.  Everything here is centred, so only
-- the vertical offsets are numbers of their own -- and they are the numbers to
-- correct against a screenshot.
local LOGO_Y, VERSION_Y = 10, 60
-- Measured off a capture of the cartridge: the PRESS START glyphs occupy rows
-- 106..111 of the 160 and the copyright line 145..150.  The first of those was
-- 88 here, which put it through the bottom of the EMERALD VERSION wordmark --
-- reported from play as "the press start text ... should be a little lower".
local PRESS_START_Y = 105
local COPYRIGHT_Y = 145

-- CENTRED ON THE INK, NOT ON THE PADDING.
--
-- Reported from play: "on the main menu the pokemon logo is left aligned
-- instead of center aligned above the emerald logo like it should be".  It
-- was, and the reason is that a GBA background bitmap is as wide as the
-- BACKGROUND: the logo is 166 pixels of art sitting against the left edge of
-- a 256-pixel sheet, and on the cartridge a scroll register puts it on
-- screen.  Centring the sheet on a 240-wide screen therefore starts it eight
-- pixels off the left and the art three pixels after that, which is what a
-- left-aligned logo looks like.
--
-- The importer measures the ink's own box (contentX / contentWidth); this
-- centres THAT, and falls back to the old behaviour for a cache that predates
-- the measurement.
local function centredX(rec, width)
  local cw = tonumber(rec.contentWidth)
  local cx = tonumber(rec.contentX)
  if cw and cx then
    return math.floor((width - cw) / 2) - cx
  end
  return math.floor((width - (tonumber(rec.width) or width)) / 2)
end

function Gen3Title:wantsFillScale() return true end

-- NOT A PANEL, so its edge is not a frame to continue.
--
-- Renderer:bleedEdges paints the letterbox with the surface's outermost row
-- and column so a menu's border appears to run to the window edge.  Here the
-- outermost column is the cartridge's title art, drawn edge to edge -- pulling it
-- outward stretches that sideways instead of extending a border.  Reported
-- from play: "fix the stretching of borders on the start menu, main menu,
-- main menu intro and the continue, new game, options, exit menus ... instead
-- make them full screen/fit the screen without stretching".  wantsFillScale
-- above is what makes it fill; this is what stops it smearing.
function Gen3Title:wantsEdgeBleed() return false end

-- Game:draw holds this surface for the whole stack above, so the menu this
-- screen opens does not snap the canvas back to 160x144 underneath it.
function Gen3Title:uiSize() return Gen3Wide.uiSize() end

-- AND IT IS NOT SHADE-REMAPPED.
--
-- Every Game Boy screen in this engine is drawn in four shades and coloured
-- by the SGB pass on the way out.  Emerald's title is already colour -- 15
-- palettes of it, loaded in one call -- and running it through that pass is
-- what turned Rayquaza black and the clouds grey.  A whole-screen true-colour
-- zone is the pass's own way of being told to leave a region alone.
function Gen3Title:sgbPalettes()
  local P = require("src.render.PaletteFX")
  local w = self:width()
  return { P.trueColorZone(0, 0, math.ceil(w / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

-- HOW WIDE THIS SCREEN IS THIS FRAME.
--
-- Asked for directly: "ensure that the main menu and intro animations extend
-- to wide screen and fill the screen without black borders".  The cartridge
-- draws 240 columns; a wide window gets the surface its own shape asks for and
-- the slack is filled with the backdrop's own sky, which is a flat colour per
-- row and so can be continued exactly (Gen3Wide, Gen3Scene.skyColumn).
--
-- Everything below is laid out against THIS, not against 240, so the logo, the
-- wordmark and the prompt stay centred on whatever the window is.
function Gen3Title:width()
  return (select(1, Gen3Wide.uiSize()))
end

function Gen3Title.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen3Title)
  self.game = game
  self.onNewGame = opts.onNewGame
  self.onContinue = opts.onContinue
  self.title = (game.data.field and game.data.field.title) or {}
  self.layers = Gen3Scene.layersOf(game.data, "title")
  if not self.layers[1] then
    Logger.warn("gen3 title: this dataset carries no title layers -- the "
                .. "screen falls back to the plain backdrop")
  end
  self.cloudY = 0
  self.blink = 0
  self.timer = 0
  return self
end

-- Reported from play: "the title music ... arent playing".  The song was
-- being asked for by a GAME BOY NAME -- Music_TitleScreen -- and a Hoenn
-- dataset has no such key: its songs are numbered, SONG_19D and the rest.  So
-- the lookup missed on every boot and the title screen came up silent.
--
-- Music.special is the join between a role and whatever this dataset calls
-- the song, and the import now answers it for Gen 3 as well.
function Gen3Title:enter()
  local data = self.game.data
  local song = self.title.music or Music.special(data, "title")
                 or "Music_TitleScreen"
  if data.audio and data.audio.songs and data.audio.songs[song] then
    pcall(Music.play, data, song)
  end
end

-- THE MAIN MENU IS ITS OWN SCREEN, and this is the whole of what used to be
-- wrong with it.  A menu opened on top of the title put a white window across
-- the middle of the POKéMON logo -- which read as the logo being misaligned,
-- when it was simply half-covered.  On the cartridge, START leaves the title
-- behind: CB2_InitMainMenu clears both backgrounds and draws the rows on a
-- plain field, and there is no logo underneath to cover.
--
-- The rows, the CONTINUE panel and the save check that decides whether
-- CONTINUE exists at all now live in Gen3MainMenu; the mod hook moved with
-- them, so a mod that adds a row still gets one.
function Gen3Title:openMenu()
  Screens.push(self.game, "Gen3MainMenu", {
    onNewGame = self.onNewGame,
    onContinue = self.onContinue,
  })
end

-- The clouds keep moving while the main menu is open, which is what the
-- cartridge does -- and the only reason they did not is that the menu is a
-- state on top of this one, so `update` stopped being called the moment it
-- opened. Everything that MOVES lives here; StateStack calls it on covered
-- states too. No input, no pushes: see the note on StateStack:update.
function Gen3Title:animate(dt)
  self.timer = self.timer + 1
  self.blink = (self.blink + 1) % 60
  -- the clouds wrap on their own height (the cartridge's background is 256
  -- tall and wraps there), not on the screen's
  self.cloudY = (self.cloudY + CLOUD_PIXELS_PER_FRAME) % 256
end

function Gen3Title:update(dt)
  self:animate(dt)
  local input = self.game.input
  if input:wasPressed("start") or input:wasPressed("a") then
    self:openMenu()
  end
end

-- THE CLOUD FIELD, ROW BY ROW.
--
-- The hardware gives every scanline its own BG1HOFS, so this does too -- but
-- it does not draw 160 separate rows: the wave is four pixels either side and
-- lands on whole pixels, so only nine offsets exist and each one owns a run of
-- consecutive rows.  One strip per run is two dozen draws rather than several
-- hundred, and the picture is identical because the rows inside a run really
-- do share an offset.
--
-- One Quad is kept and re-aimed with setViewport, so a frame allocates
-- nothing (see the frame-budget pass).
function Gen3Title:drawClouds(image, iw, ih, W)
  local quad = self.cloudQuad
  if not quad then
    quad = love.graphics.newQuad(0, 0, iw, 1, iw, ih)
    self.cloudQuad = quad
  end
  local top = math.floor(self.cloudY) % ih
  local phase = (self.timer * CLOUD_WAVE_ROWS_PER_FRAME) % CLOUD_WAVE_ROWS
  local row = 0
  while row < GBA_H do
    -- how far this run goes: rows share it while the offset AND the source
    -- rows stay contiguous, so a wrap through the map's own 256 ends a run
    local offset = cloudWave(row, phase)
    local src = (top + row) % ih
    local height = 1
    while row + height < GBA_H
          and cloudWave(row + height, phase) == offset
          and (src + height) < ih do
      height = height + 1
    end
    quad:setViewport(0, src, iw, height, iw, ih)
    local x = offset - iw
    while x < W do
      love.graphics.draw(image, quad, x, row)
      x = x + iw
    end
    row = row + height
  end
end

function Gen3Title:draw()
  local data = self.game.data
  local W = self:width()
  local inset = Gen3Wide.inset(W)
  love.graphics.setColor(0.04, 0.09, 0.16, 1)
  love.graphics.rectangle("fill", 0, 0, W, GBA_H)

  local ids = self.layers
  love.graphics.setColor(1, 1, 1, 1)
  for i, id in ipairs(ids) do
    local image = Gen3Scene.image(data, id, i == 1)
    if image then
      local iw, ih = image:getDimensions()
      if i == 1 then
        -- THE BACKDROP, and the sky either side of it.
        --
        -- Only the cartridge's own 240 columns carry the picture -- the rest
        -- of its 256-wide background is unused and black -- so the picture is
        -- drawn at the inset and the slack is filled with each row's own
        -- colour, which is what that row already is from edge to edge.
        Gen3Wide.fillSides(Gen3Scene.skyColumn(data, id, GBA_W, GBA_H),
                           W, GBA_H)
        love.graphics.setColor(1, 1, 1, 1)
        local quad = love.graphics.newQuad(0, 0, math.min(GBA_W, iw),
                                           math.min(GBA_H, ih), iw, ih)
        love.graphics.draw(image, quad, inset, 0)
        -- ...AND THE GLOW, over the backdrop and under the clouds, which is
        -- where it sits on the cartridge: the markings are part of this
        -- background, and the cloud field drifts in front of them.
        local bank, index = Gen3Scene.animatedEntry(data, id)
        if bank then
          local mask = Gen3Scene.maskImage(data, id, bank, index)
          if mask then
            local phase = (self.timer % GLOW_FRAMES) / GLOW_FRAMES
            local a = 0.5 - 0.5 * math.cos(phase * 2 * math.pi)
            love.graphics.setColor(GLOW[1], GLOW[2], GLOW[3], a)
            love.graphics.draw(mask, quad, inset, 0)
            love.graphics.setColor(1, 1, 1, 1)
          end
        end
      else
        -- THE CLOUD FIELD, all the way across and drifting UP through the
        -- wave (see the note on CLOUD_PIXELS_PER_FRAME).  It is a background
        -- the cartridge scrolls and wraps at its own 256 -- so it tiles, and
        -- on a wider screen it simply tiles further rather than stopping
        -- where the Game Boy's screen would have.
        self:drawClouds(image, iw, ih, W)
      end
    end
  end

  -- THE BRANDING, in the cartridge's own pixels where the dataset has them.
  --
  -- The logo is the 8bpp bitmap; the wordmark is the one sprite sheet on this
  -- screen that came out 8bpp, which is what tells it apart from the PRESS
  -- START strip and the logo shine without naming an address here.
  love.graphics.setColor(1, 1, 1, 1)
  local drewBrand = false
  local logo, logoRec = Gen3Scene.overlayImage(data, "title", "bitmaps", 1)
  if logo and logoRec then
    love.graphics.draw(logo, centredX(logoRec, W), LOGO_Y)
    drewBrand = true
  end
  local record = Gen3Scene.overlays(data, "title")
  local strip = nil
  for n, sheet in ipairs((record or {}).sheets or {}) do
    if sheet.depth == 8 and sheet.layout ~= "strip" then
      local image, rec = Gen3Scene.overlayImage(data, "title", "sheets", n)
      if image and rec then
        love.graphics.draw(image, centredX(rec, W), VERSION_Y)
        drewBrand = true
      end
    elseif sheet.layout == "strip" and sheet.pieces and not strip then
      strip = { n = n, sheet = sheet }
    end
  end

  -- The fallback, for a dataset whose overlay pass found nothing: the words
  -- set in the cartridge's own font over a band dark enough to read them.
  local prompt = Strings("PRESS START")
  local promptY = GBA_H - 34
  local GameVersion = require("src.core.GameVersion")
  local fireRed = GameVersion.isFRLG()
  if not drewBrand then
    local brand = self.title.brandText
                  or (fireRed and Strings("POKéMON FIRERED"))
                  or Strings("POKéMON EMERALD")
    local bandY = GBA_H - 40
    love.graphics.setColor(0.04, 0.09, 0.16, 0.72)
    love.graphics.rectangle("fill", 0, bandY, W, 40)
    love.graphics.setColor(1, 1, 1, 1)
    Font.draw(brand, math.floor((W - Font.width(brand)) / 2), bandY + 6)
    -- Keep the FireRed fallback prompt below its wordmark; Emerald uses the
    -- measured cartridge prompt position below.
    promptY = bandY + 22
  end

  -- PRESS START AND THE COPYRIGHT, IN THE CARTRIDGE'S OWN PIXELS.
  --
  -- Reported from play: "the press start text has the wrong font compared to
  -- the actual rom".  It was the ENGINE's font, because these two lines are
  -- not text on this cartridge at all -- they are one 4bpp sprite sheet
  -- (tag 03E9) holding both captions end to end, which the overlay pass
  -- extracted and nothing drew.  The importer now cuts it at its own blank
  -- tiles, so `pieces` is { PRESS START, the copyright } in the order the
  -- cartridge stores them.
  --
  -- Only the first blinks: the copyright stands.
  local drewPrompt = false
  if strip then
    local pieces = strip.sheet.pieces
    for k = 1, math.min(2, #pieces) do
      local rec = pieces[k]
      local image = Gen3Scene.pieceImage(data, "title", strip.n, k)
      if image and rec then
        local blinking = (k == 1)
        if not blinking or self.blink < 40 then
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(image,
            math.floor((W - (tonumber(rec.width) or 0)) / 2),
            blinking and PRESS_START_Y or COPYRIGHT_Y)
        end
        if blinking then drewPrompt = true end
      end
    end
  end
  if not drewPrompt and self.blink < 40 then
    local px = math.floor((W - Font.width(prompt)) / 2)
    Font.draw(prompt, px, fireRed and promptY or PRESS_START_Y)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3Title
