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

-- the clouds slide sideways the way ScrollTitleScreenClouds does
local CLOUD_PIXELS_PER_FRAME = 1 / 8

-- MEASURED, not derived (see the note at the top of this file): where the two
-- pieces of branding sit on the 240x160 screen.  Both are centred, so only the
-- vertical offsets are numbers of their own.
local LOGO_Y, VERSION_Y = 10, 60

function Gen3Title:wantsFillScale() return true end

-- Game:draw holds this surface for the whole stack above, so the menu this
-- screen opens does not snap the canvas back to 160x144 underneath it.
function Gen3Title:uiSize() return GBA_W, GBA_H end

-- AND IT IS NOT SHADE-REMAPPED.
--
-- Every Game Boy screen in this engine is drawn in four shades and coloured
-- by the SGB pass on the way out.  Emerald's title is already colour -- 15
-- palettes of it, loaded in one call -- and running it through that pass is
-- what turned Rayquaza black and the clouds grey.  A whole-screen true-colour
-- zone is the pass's own way of being told to leave a region alone.
function Gen3Title:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
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
  self.cloudX = 0
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
  self.cloudX = (self.cloudX + CLOUD_PIXELS_PER_FRAME) % GBA_W
end

function Gen3Title:update(dt)
  self:animate(dt)
  local input = self.game.input
  if input:wasPressed("start") or input:wasPressed("a") then
    self:openMenu()
  end
end

function Gen3Title:draw()
  local data = self.game.data
  love.graphics.setColor(0.04, 0.09, 0.16, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)

  local ids = self.layers
  love.graphics.setColor(1, 1, 1, 1)
  for i, id in ipairs(ids) do
    local image = Gen3Scene.image(data, id, i == 1)
    if image then
      local iw, ih = image:getDimensions()
      local quad = love.graphics.newQuad(0, 0, math.min(GBA_W, iw),
                                         math.min(GBA_H, ih), iw, ih)
      if i == 1 then
        love.graphics.draw(image, quad, 0, 0)
      else
        -- the cloud field wraps: draw it twice, offset, so the seam is
        -- always off-screen
        local shift = -math.floor(self.cloudX)
        love.graphics.draw(image, quad, shift, 0)
        love.graphics.draw(image, quad, shift + GBA_W, 0)
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
    love.graphics.draw(logo, math.floor((GBA_W - logoRec.width) / 2), LOGO_Y)
    drewBrand = true
  end
  local record = Gen3Scene.overlays(data, "title")
  for n, sheet in ipairs((record or {}).sheets or {}) do
    if sheet.depth == 8 and sheet.layout ~= "strip" then
      local image, rec = Gen3Scene.overlayImage(data, "title", "sheets", n)
      if image and rec then
        love.graphics.draw(image, math.floor((GBA_W - rec.width) / 2),
                           VERSION_Y)
        drewBrand = true
      end
      break
    end
  end

  -- The fallback, for a dataset whose overlay pass found nothing: the words
  -- set in the cartridge's own font over a band dark enough to read them.
  local prompt = Strings("PRESS START")
  if not drewBrand then
    local brand = self.title.brandText or Strings("POKéMON EMERALD")
    local bandY = GBA_H - 40
    love.graphics.setColor(0.04, 0.09, 0.16, 0.72)
    love.graphics.rectangle("fill", 0, bandY, GBA_W, 40)
    love.graphics.setColor(1, 1, 1, 1)
    Font.draw(brand, math.floor((GBA_W - Font.width(brand)) / 2), bandY + 6)
  end
  if self.blink < 40 then
    -- PRESS START blinks low on the screen, where the cartridge puts it
    local px = math.floor((GBA_W - Font.width(prompt)) / 2)
    Font.draw(prompt, px, GBA_H - 34)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3Title
