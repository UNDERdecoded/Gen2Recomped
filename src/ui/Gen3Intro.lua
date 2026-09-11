-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Emerald's attract movie: the wet leaves, then the bike ride.
--
-- WHY THIS IS NOT IntroMovie.  Gen 3 was booting straight to the title --
-- `boot.screens.splash = false` -- which silently dropped the STUDIO CARD,
-- and that card is not a Gen 1 asset: it is this port's own.  Sending Gen 3
-- to IntroMovie instead would have been the other mistake: everything after
-- the card in it is Kanto -- the shooting star, the Gengar and Nidorino
-- fight -- built out of a `field.intro` manifest a Gen 3 cache does not have
-- and should not inherit.  So the card is kept and the movie behind it is
-- Emerald's.
--
-- THE CLOCK IS THE CARTRIDGE'S, and that is the thing that changed this from
-- a slideshow into a film.  Emerald's intro is one task chain counting frames
-- from zero, and every beat in it is a comparison against that counter.  A
-- scanner walked the chain tracking registers and recorded every immediate
-- the counter is compared against -- some as `cmp rD,#imm`, the larger ones
-- built with `movs`+`lsls` and compared register to register -- and what came
-- back was: 76, 128, 251, 256, 368, 384, 560 in the first scene's handler;
-- 832 and 1007 in the one after it; 1026 where it hands over; and 1088, 1109,
-- 1168, 1214, 1224, 1394, 1398, 1576, 1856, 1946 in the ride.  Those are the
-- beats below, and they are why the film is 1946 frames rather than however
-- long a made-up per-scene timer said.
--
-- WHICH LAYERS COEXIST IS ALSO IN THE DATA.  Every layer records the VRAM
-- address it is decompressed to.  Layers that share one are the SAME
-- background at different moments -- the cartridge overwrites the slot -- so
-- they are a sequence; a layer with an address of its own is a background of
-- its own and is on screen the whole time.  Drawing all of them one at a
-- time, which is what this did, showed the standing layer as a scene in its
-- own right and then took it away again: the flashes.
--
-- THE OPENING SHOT is one sheet with FOUR tilemaps -- four backgrounds
-- stacked, which is how the leaves sit in front of the plants in front of the
-- hills -- and the scene pass, which pairs one sheet with one tilemap, could
-- not see it at all.  The import composes each layer on its own, index 0 left
-- transparent except on the backdrop.
--
-- AND THE CAST IS THE CARTRIDGE'S.  Four compressed sprite sheets carry the
-- ride -- the two riders' seven-frame pedal cycles, the bicycle, the Pokemon
-- -- and three more carry the opening shot: the water drops and their ripple
-- rings, the sparkles, and the winged silhouette the scene puts in the sky at
-- frame 832.  Their OAM shapes are a judgement (a sprite's shape lives in a
-- template no loader touches) corroborated by the composed picture: at any
-- other size those sheets are noise.
--
-- WHAT IS STILL RECONSTRUCTED is the geometry -- where a drop's leaf runs,
-- where the rider stands, how far the sparkles are apart.  The cartridge's
-- own answers to those live in sprite callbacks and coordinate tables this
-- pass does not read.  Every beat is derived; every position is not, and the
-- constants below say which is which.
--
-- ONE DELIBERATE DIFFERENCE.  At frame 128 the cartridge fades its own studio
-- logo in over the leaves and blends it out again at 272.  This port shows
-- ITS card in that slot, on the cartridge's own beats, over the cartridge's
-- own shot -- so the lettering frames in the drops sheet are extracted and
-- never drawn.
--
-- START, A or B skips it the way CheckForUserInterruption always has.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Gen3Scene = require("src.render.Gen3Scene")
local Music = require("src.core.Music")
local Strings = require("src.core.Strings")

local Gen3Intro = {}
Gen3Intro.__index = Gen3Intro
Gen3Intro.isOpaque = true

local GBA_W, GBA_H = 240, 160

-- DERIVED: the immediates the intro's own task chain compares its frame
-- counter against.  See the note at the top for how they were found.
local T_BIG_DROP       = 76      -- the first drop starts down the leaf
local T_LOGO_APPEAR    = 128     -- the studio card fades in over the shot
local T_LOGO_LETTERS   = 144     -- ...and is fully up
local T_BIG_DROP_FALLS = 251     -- it lets go
local T_LOGO_BLEND_OUT = 256     -- the card starts to go
local T_LOGO_GONE      = 272
local T_SMALL_DROP_1   = 368
local T_SMALL_DROP_2   = 384
local T_SPARKLES       = 560     -- sparkles, and the camera starts climbing
local T_FLYGON         = 832     -- the silhouette crosses the sky
-- 904 is the one beat the scan did not come back with -- it is built some
-- other way than the immediates around it.  It is where the climb stops.
local T_PAN_UP_END     = 904
local T_SCENE_1_END    = 1007
local T_SCENE_2        = 1026    -- the ride begins
local T_MANECTRIC      = 1088
local T_DRIFT_BACK     = 1109
local T_RUN_CIRCULAR   = 1168
local T_MOVE_FORWARD   = 1214
local T_TORCHIC        = 1224
local T_FLYGON_ENTER   = 1394
local T_MOVE_BACKWARD  = 1398
local T_HOLD_POSITION  = 1576
local T_TORCHIC_EXIT   = 1856
local T_SCENE_2_END    = 1946

local FADE_FRAMES = 20

-- RECONSTRUCTED geometry.  None of this is in the cartridge's tables; it is
-- built to sit on the beats above.
local RIDER_Y = 100             -- pret creates the rider at y=100
local RIDER_ENTER_X = GBA_W + 32 -- ...at DISPLAY_WIDTH + 32
local PEDAL_FRAMES = 5          -- frames per pedal pose
local RIDE_SPEED = 2.0          -- pixels of world per frame
local POKEMON_ENTER_X = -64     -- pret creates the Pokemon at (-64, 60)
local POKEMON_Y = 60
local POKEMON_SPEED = 0.9
local POKEMON_ARC = 48          -- Sin(t >> 2 & 0x7F, 48), one arc over 512
local POKEMON_ARC_FRAMES = 512
-- HOW THE OPENING SHOT IS STAGED.
--
-- THERE IS NO POND ASSET, and that is the thing that took longest to accept.
-- The scene decompresses ONE sheet and four tilemaps and nothing else, so the
-- water is not a picture to go and find -- it is composed out of the four
-- layers, and getting it on screen is a staging problem rather than an
-- extraction one.
--
-- What each layer holds, read off the composed tilemaps:
--   0  the big leaves across the top, a transparent middle, a dark bank of
--      grass along the bottom -- the nearest thing to the lens
--   1  a hedge along its top, solid dark green below it
--   2  grass tufts and a leaf bed along its top, solid dark green below
--   3  the backdrop: sky, mountains, a green field, and then a pale flat
--      band across its bottom third.  That band is the water.
--
-- Stacked at a common offset -- which is what this did -- layers 1 and 2 lay
-- their dark green over the whole lower screen and the water is buried under
-- it.  That was the missing pond: not absent, covered.
--
-- So the three near layers are STAGED rather than stacked: the leaves at the
-- top of the frame, the two banks pushed down until only their top strips
-- show along the bottom, and the backdrop framed so its pale band sits in the
-- gap between them.  A drop then runs down a leaf, falls through open air and
-- lands in water, which is the shot.  Every number here is reconstruction --
-- the cartridge scrolls its four backgrounds independently and none of those
-- offsets is a table anyone can read.
local SHOT_BACKDROP_TOP = 78    -- the backdrop's window: water in the lower half
local SHOT_BANKS = { 0, 124, 138 }  -- screen y of each near layer, front first
local WATER_Y = 110             -- the middle of the band the banks leave open
local RIPPLE_Y = WATER_Y        -- so a drop lands in it and rings
local RIPPLE_FRAMES = 24
local DANGLE_FRAMES = 24        -- it hangs off the leaf before letting go
local SPARKLE_COUNT = 11        -- pret spawns eleven, twelve frames apart
local SPARKLE_GAP = 12
local SPARKLE_LIFE = 48

-- The three drops the cartridge creates, with the arguments it passes:
-- CreateWaterDrop(x, y, speed, delay, gravity, small).  Speed and gravity are
-- 8.8 fixed point, so they divide by 256 to get pixels per frame.
-- `tipX`/`tipY` are RECONSTRUCTION: the cartridge's drop follows the leaf it
-- is on, and where that leaf runs is in the sprite callback, not in any table.
-- What is the cartridge's is where each drop STARTS, how fast it moves, how
-- hard it falls, and -- for the first one -- the frame it lets go on.
local DROPS = {
  { at = T_BIG_DROP,     x = 236, y = -14, tipX = 150, tipY = 58,
    gravity = 0x78, falls = T_BIG_DROP_FALLS, small = false },
  { at = T_SMALL_DROP_1, x = 48,  y = 0,   tipX = 86,  tipY = 52,
    gravity = 0x70, small = true },
  { at = T_SMALL_DROP_2, x = 200, y = 30,  tipX = 186, tipY = 56,
    gravity = 0x80, small = true },
}
-- the big drop's slide is the cartridge's: spawned at 76, it lets go at 251.
-- The small ones carry no recorded beat, so they slide for the same span --
-- which puts both of them down just before the camera starts to climb.
local SLIDE_FRAMES = T_BIG_DROP_FALLS - T_BIG_DROP

-- Reported from play: "the ... main menu intro music/sounds arent playing".
-- The intro had a `Music.stop` on its way out and nothing on its way in, so
-- Emerald's opening demo ran in silence and handed a silent title screen on.
function Gen3Intro:enter()
  local data = self.game and self.game.data
  local song = data and Music.special(data, "intro")
  if song and data.audio and data.audio.songs and data.audio.songs[song] then
    pcall(Music.play, data, song)
  end
end

function Gen3Intro:wantsFillScale() return true end
function Gen3Intro:uiSize() return GBA_W, GBA_H end

-- colour, not four shades: see the note on Gen3Title:sgbPalettes
function Gen3Intro:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

function Gen3Intro.new(game, onDone)
  local self = setmetatable({}, Gen3Intro)
  self.game = game
  self.onDone = onDone
  self.frame = 0
  self.finished = false
  local intro = (game.data.field and game.data.field.intro) or {}
  self.studio = intro.studio or {}
  self.skipAll = intro.skip and true or false
  self.skies = Gen3Scene.layersOf(game.data, "intro")

  -- Split the role's layers by the VRAM address each is loaded to (see the
  -- note at the top): a shared address means one background taking turns,
  -- a private one means a layer that stands through all of them.
  local scenes = (game.data.scenes) or {}
  local uses = {}
  for _, id in ipairs(self.skies) do
    local dest = scenes[id] and scenes[id].graphicsDest
    if dest then uses[dest] = (uses[dest] or 0) + 1 end
  end
  self.standing, self.sequence = {}, {}
  for _, id in ipairs(self.skies) do
    local dest = scenes[id] and scenes[id].graphicsDest
    if dest and (uses[dest] or 0) > 1 then
      self.sequence[#self.sequence + 1] = id
    else
      self.standing[#self.standing + 1] = id
    end
  end
  -- a dataset whose layers all landed in their own slot has no sequence to
  -- run; then every layer takes a turn, which is what this used to do
  if not self.sequence[1] then
    self.sequence, self.standing = self.skies, {}
  end

  self.cast = (game.data.constants or {}).gen3IntroCast
  self.shot = ((game.data.constants or {}).gen3IntroShots or {}).leaves
  self.rideX = 0
  return self
end

-- The opening shot's layers, back to front.  Empty for a dataset without it,
-- and the intro then plays as a card over the skies the way it used to.
function Gen3Intro:shotLayers()
  local record = self.shot
  if type(record) ~= "table" then return nil end
  if self.cachedLayers ~= nil then
    return self.cachedLayers[1] and self.cachedLayers or nil
  end
  local out = {}
  for n, layer in ipairs(record.layers or {}) do
    local ok, image = pcall(Assets.image, layer.image)
    if ok and image then
      out[#out + 1] = { image = image, backdrop = layer.backdrop, order = n }
    end
  end
  -- the backdrop first, then the cut-outs in the order the cartridge LOADS
  -- them, which is front to back -- staging them depends on knowing which is
  -- which, and table.sort is not stable, so the load index is the tie-break
  table.sort(out, function(a, b)
    local ab, bb = a.backdrop and 1 or 0, b.backdrop and 1 or 0
    if ab ~= bb then return ab > bb end
    return a.order < b.order
  end)
  self.cachedLayers = out
  return out[1] and out or nil
end

-- One of the shot's sprite sheets, and the quad for a frame of it.  The
-- import lays each sheet out as its frames side by side, so a frame is a
-- straight slice; a sheet the discovery pass could not name a shape for has
-- one frame and is never asked for a second.
function Gen3Intro:shotSprite(role, frame)
  local sprites = self.shot and self.shot.sprites
  local record = type(sprites) == "table" and sprites[role]
  if type(record) ~= "table" or not record.image then return nil end
  local ok, image = pcall(Assets.image, record.image)
  if not ok or not image then return nil end
  local frames = math.max(1, math.floor(tonumber(record.frames) or 1))
  local fw = math.floor(tonumber(record.frameWidth) or 32)
  local fh = math.floor(tonumber(record.frameHeight) or 32)
  local iw, ih = image:getDimensions()
  local at = (math.floor(frame or 0) % frames) * fw
  return image, love.graphics.newQuad(at, 0, fw, fh, iw, ih), fw, fh, record
end

-- One actor's sheet and the quad for a frame of it.
function Gen3Intro:actor(name, frame)
  local record = self.cast and self.cast[name]
  if type(record) ~= "table" or not record.image then return nil end
  local ok, image = pcall(Assets.image, record.image)
  if not ok or not image then return nil end
  local frames = math.max(1, math.floor(tonumber(record.frames) or 1))
  local fw = math.floor(tonumber(record.frameWidth) or 64)
  local fh = math.floor(tonumber(record.frameHeight) or 64)
  -- A SHEET IS NOT ALWAYS ONE ANIMATION.  Torchic's six frames are four of it
  -- running and two of it on its side; cycling all six made it fall over once
  -- a second, which is not what it does on the cartridge.  The import works
  -- out how many belong to the first animation from the frames' own shapes.
  local cycle = math.max(1, math.min(frames,
                                     math.floor(tonumber(record.runFrames)
                                                or frames)))
  local iw, ih = image:getDimensions()
  local at = (math.floor(frame or 0) % cycle) * fw
  return image, love.graphics.newQuad(at, 0, fw, fh, iw, ih), fw, fh
end

-- Which rider a save carries.  Before the Birch speech has been answered
-- there is no gender on the save, and the boy is the cartridge's own default.
function Gen3Intro:riderName()
  local player = (self.game.save or {}).player or {}
  if player.gender == "girl" and self.cast and self.cast.riderGirl then
    return "riderGirl"
  end
  return (self.cast and self.cast.riderBoy) and "riderBoy" or "riderGirl"
end

function Gen3Intro:finish()
  if self.finished then return end
  self.finished = true
  pcall(Music.stop)
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

function Gen3Intro:update(dt)
  if self.skipAll then self:finish() return end
  local input = self.game.input
  if input:wasPressed("a") or input:wasPressed("b")
     or input:wasPressed("start") then
    self:finish()
    return
  end
  self.frame = self.frame + 1
  -- the world keeps moving across a cut, so the ride's odometer runs the
  -- whole film rather than restarting with each shot
  self.rideX = self.rideX + RIDE_SPEED
  if self.frame >= T_SCENE_2_END then self:finish() end
end

-- ---------------------------------------------------------------------------
-- SCENE ONE: the leaves.

-- Where the camera is.  It holds on the leaves until the sparkles and then
-- climbs out of them, which is the span the pan-up task runs over.
function Gen3Intro:panProgress()
  local span = T_PAN_UP_END - T_SPARKLES
  return math.min(1, math.max(0, (self.frame - T_SPARKLES) / span))
end

function Gen3Intro:drawShot(layers)
  local progress = self:panProgress()
  love.graphics.setColor(1, 1, 1, 1)
  local bank = 0
  for _, layer in ipairs(layers) do
    local iw, ih = layer.image:getDimensions()
    local top, y = 0, 0
    if layer.backdrop then
      -- the camera tilts up: the far picture's window climbs toward its sky,
      -- and on the way the water it opened on slides out of the bottom
      top = math.floor(math.min(math.max(0, ih - GBA_H), SHOT_BACKDROP_TOP)
                       * (1 - progress))
    else
      bank = bank + 1
      y = SHOT_BANKS[math.min(bank, #SHOT_BANKS)] or 0
      -- ...and everything near the camera swings DOWN across the frame and
      -- off the bottom of it, which is what a tilt up does to a leaf a foot
      -- from the lens
      y = y + math.floor(progress * progress * (GBA_H + 64))
    end
    local slice = math.min(GBA_H - math.min(y, GBA_H), ih - top)
    if slice > 0 then
      local quad = love.graphics.newQuad(0, top, iw, slice, iw, ih)
      love.graphics.draw(layer.image, quad,
                         math.floor((GBA_W - math.min(GBA_W, iw)) / 2), y)
    end
  end
end

-- A drop, at whatever point of its life this frame catches it: running down
-- the leaf, hanging off the end of it, falling, or ringing in the water where
-- it landed.  The cartridge's own chain is
-- slide -> reach the leaf end -> dangle -> fall -> ripple, and that is the
-- shape here; the leaf it runs along is the reconstructed part.
function Gen3Intro:drawDrops()
  local sheet, _, fw, fh, record = self:shotSprite("drops", 0)
  if not sheet then return end
  local dropFrame = math.floor(tonumber(record.drop) or 0)
  local ripple = type(record.ripple) == "table" and record.ripple or nil
  for _, d in ipairs(DROPS) do
    local age = self.frame - d.at
    if age >= 0 then
      local slide = (d.falls or (d.at + SLIDE_FRAMES)) - d.at
      local scale = d.small and 0.6 or 1
      local frame, x, y, alpha = dropFrame, d.x, d.y, 1
      local alive = true
      if age < slide then
        -- along the leaf, easing to a stop at the tip, then dangling there
        local run = math.min(1, age / math.max(1, slide - DANGLE_FRAMES))
        local eased = run * run * (3 - 2 * run)
        x = d.x + (d.tipX - d.x) * eased
        y = d.y + (d.tipY - d.y) * eased
        if age > slide - DANGLE_FRAMES then
          y = y + math.sin((age - (slide - DANGLE_FRAMES)) * 0.35) * 1.5
        end
      else
        -- and off it: v = g*t, so the distance is g*t*t/2
        local fell = age - slide
        local g = d.gravity / 256
        x = d.tipX
        y = d.tipY + g * fell * fell / 2
        if y >= RIPPLE_Y then
          -- the ring, at the moment and place it landed
          local landed = math.sqrt(math.max(0, 2 * (RIPPLE_Y - d.tipY) / g))
          local since = fell - landed
          if since > RIPPLE_FRAMES or not ripple then
            alive = false
          else
            y = RIPPLE_Y
            local step = 1 + math.floor(since / (RIPPLE_FRAMES / #ripple))
            frame = math.floor(tonumber(ripple[math.min(step, #ripple)])
                               or dropFrame)
            alpha = 1 - since / RIPPLE_FRAMES
            scale = scale * (1 + since / RIPPLE_FRAMES)
          end
        end
      end
      if alive and y > -fh and y < GBA_H + fh then
        local img, quad = self:shotSprite("drops", frame)
        if img and quad then
          love.graphics.setColor(1, 1, 1, alpha)
          love.graphics.draw(img, quad,
                             math.floor(x - fw / 2 * scale),
                             math.floor(y - fh / 2 * scale), 0, scale, scale)
        end
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Eleven sparkles, twelve frames apart, from the beat the cartridge starts
-- them on.  Where they sit is reconstruction: the cartridge reads them out of
-- a coordinate table this pass does not find, so they are spread across the
-- picture on a fixed pattern rather than at random -- an intro that flickers
-- differently every boot would be worse than one that is merely not theirs.
function Gen3Intro:drawSparkles()
  local sheet = self:shotSprite("sparkle", 0)
  if not sheet or self.frame < T_SPARKLES then return end
  for i = 0, SPARKLE_COUNT - 1 do
    local born = T_SPARKLES + i * SPARKLE_GAP
    local age = self.frame - born
    if age >= 0 and age < SPARKLE_LIFE then
      local img, quad, fw, fh = self:shotSprite("sparkle",
                                                math.floor(age / 8))
      if img and quad then
        local x = 16 + ((i * 73) % 200)
        local y = 20 + ((i * 47) % 110)
        local a = 1 - age / SPARKLE_LIFE
        love.graphics.setColor(1, 1, 1, a)
        love.graphics.draw(img, quad, x - fw / 2, y - fh / 2)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- The silhouette that crosses the sky once the camera is out of the leaves.
function Gen3Intro:drawSilhouette()
  if self.frame < T_FLYGON then return end
  local img, quad, fw = self:shotSprite("flygon", 0)
  if not img or not quad then return end
  local age = self.frame - T_FLYGON
  local span = math.max(1, T_SCENE_1_END - T_FLYGON)
  local x = GBA_W + fw - (GBA_W + fw * 2) * (age / span)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, quad, math.floor(x),
                     math.floor(24 + math.sin(age / 24) * 6))
end

-- This port's studio card, drawn on the cartridge's own logo beats.
function Gen3Intro:drawCard(alpha)
  local credit = self.studio.credit or Strings("UNDERdecodedHD")
  local author = self.studio.author or "UNDERdecodedHD"
  local year = self.studio.year or "2026"
  love.graphics.setColor(1, 1, 1, alpha or 1)
  local function centre(text, y)
    Font.draw(text, math.floor((GBA_W - Font.width(text)) / 2), y)
  end
  centre(year, 56)
  centre(credit, 76)
  centre(author, 96)
  love.graphics.setColor(1, 1, 1, 1)
end

-- How far up the card is, on the cartridge's beats: in over 128..144, held,
-- out over 256..272.
function Gen3Intro:cardAlpha()
  local f = self.frame
  if f < T_LOGO_APPEAR or f >= T_LOGO_GONE then return 0 end
  if f < T_LOGO_LETTERS then
    return (f - T_LOGO_APPEAR) / (T_LOGO_LETTERS - T_LOGO_APPEAR)
  end
  if f < T_LOGO_BLEND_OUT then return 1 end
  return 1 - (f - T_LOGO_BLEND_OUT) / (T_LOGO_GONE - T_LOGO_BLEND_OUT)
end

-- ---------------------------------------------------------------------------
-- SCENE TWO: the ride.

-- Where the rider is.  The beats are the cartridge's; the stations between
-- them are not, so they are keyframes here and the rider eases between them.
local RIDER_TRACK = {
  { T_SCENE_2,       RIDER_ENTER_X },
  { T_MANECTRIC,     120 },
  { T_DRIFT_BACK,    120 },
  { T_RUN_CIRCULAR,  88 },
  { T_MOVE_FORWARD,  72 },
  { T_TORCHIC,       96 },
  { T_FLYGON_ENTER,  144 },
  { T_MOVE_BACKWARD, 144 },
  { T_HOLD_POSITION, 96 },
  { T_TORCHIC_EXIT,  96 },
  { T_SCENE_2_END,   96 },
}

-- THE THREE THAT RUN ALONGSIDE, on the beats the cartridge gives them.
--
-- They were missing from the ride entirely -- the collector that finds the
-- intro's sheets only kept blobs a whole number of 64x64 frames long, and two
-- of these three are smaller than one.  `at` and `until_` are the cartridge's
-- own frame numbers; where each one runs is not.
--
-- They run BESIDE the rider, not through him.  The first cut put Manectric on
-- the same square as the bicycle, which hid the bicycle completely -- the
-- rider looked like he was sitting on a Manectric, and the bike read as
-- missing.  The ground line is the rider's; the stations are apart.
local RUNNERS = {
  { name = "manectric", at = T_MANECTRIC, y = 118, from = -72, to = 8,
    settle = T_RUN_CIRCULAR, cycle = 6 },
  { name = "torchic", at = T_TORCHIC, until_ = T_TORCHIC_EXIT, y = 126,
    from = -40, to = 74, settle = T_FLYGON_ENTER, cycle = 5 },
  { name = "volbeat", at = T_RUN_CIRCULAR, y = 44, from = GBA_W + 32,
    to = 196, settle = T_MOVE_FORWARD, cycle = 8 },
}

function Gen3Intro:drawRunners()
  for _, r in ipairs(RUNNERS) do
    if self.frame >= r.at and (not r.until_ or self.frame < r.until_) then
      local img, quad, fw, fh = self:actor(r.name,
                                           math.floor(self.rideX / r.cycle))
      if img and quad then
        local span = math.max(1, r.settle - r.at)
        local t = math.min(1, (self.frame - r.at) / span)
        t = t * t * (3 - 2 * t)
        local x = r.from + (r.to - r.from) * t
        -- a small bob, so a runner reads as running rather than sliding
        local bob = math.sin(self.frame / 5) * 1.5
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, quad, math.floor(x),
                           math.floor(r.y - fh / 2 + bob))
      end
    end
  end
end

function Gen3Intro:riderX()
  local f = self.frame
  for i = 1, #RIDER_TRACK - 1 do
    local a, b = RIDER_TRACK[i], RIDER_TRACK[i + 1]
    if f < b[1] then
      local span = math.max(1, b[1] - a[1])
      local t = math.min(1, math.max(0, (f - a[1]) / span))
      -- ease in and out, so a station is arrived at rather than snapped to
      t = t * t * (3 - 2 * t)
      return a[2] + (b[2] - a[2]) * t
    end
  end
  return RIDER_TRACK[#RIDER_TRACK][2]
end

function Gen3Intro:drawRide()
  local data = self.game.data
  -- the sequence takes its turns across the ride rather than on a timer of
  -- its own, so the film is as long as the cartridge's clock says
  local span = T_SCENE_2_END - T_SCENE_2
  local into = math.max(0, self.frame - T_SCENE_2)
  local count = math.max(1, #self.sequence)
  local index = math.min(count, 1 + math.floor(into / (span / count)))
  local within = (into % (span / count)) / (span / count)

  local function paint(id, opaque, parallax)
    local image = id and Gen3Scene.image(data, id, opaque)
    if not image then return false end
    local iw, ih = image:getDimensions()
    -- the WINDOW travels vertically, not the picture: moving the draw
    -- position instead slides the same top slice off and leaves black
    local travel = math.max(0, ih - GBA_H)
    local top = math.floor(travel * within)
    local quad = love.graphics.newQuad(0, top, iw, math.min(GBA_H, ih), iw, ih)
    -- A LAYER SCROLLS SIDEWAYS AND WRAPS, which is what makes it a ride:
    -- these maps are 256 wide against a 240 screen, so panning them without
    -- wrapping moves sixteen pixels and looks like a still.
    local shift = -math.floor(self.rideX * (parallax or 1)) % iw
    love.graphics.draw(image, quad, shift, 0)
    love.graphics.draw(image, quad, shift - iw, 0)
    return true
  end

  local drew = paint(self.sequence[index], true, 0.35)
  for i, id in ipairs(self.standing) do
    drew = paint(id, false, 0.8 + i * 0.2) or drew
  end

  -- THE POKEMON crosses behind the rider on its own beat, riding one arc of
  -- the cartridge's own sine: Sin(t >> 2 & 0x7F, 48) is half a period, so it
  -- rises and falls exactly once over the 512 frames the counter runs for.
  love.graphics.setColor(1, 1, 1, 1)
  if self.frame >= T_FLYGON_ENTER then
    local age = self.frame - T_FLYGON_ENTER
    -- ONE 128x64 picture, not two 64x64 ones: split down the middle it drew
    -- as two halves of the same Pokemon side by side.
    local mon, monQuad, monW = self:actor("pokemon", 0)
    if mon and monQuad then
      local x = POKEMON_ENTER_X + age * POKEMON_SPEED
      local arc = math.sin(math.min(age, POKEMON_ARC_FRAMES)
                           / POKEMON_ARC_FRAMES * math.pi) * POKEMON_ARC
      if x < GBA_W + monW then
        love.graphics.draw(mon, monQuad, math.floor(x),
                           math.floor(POKEMON_Y - arc))
      end
    end
  end

  -- the three that run with him, behind the rider so he stays in front
  self:drawRunners()

  -- THE BICYCLE IS ITS OWN SHEET, and the rider sits on it.
  --
  -- This has been wrong in both directions.  Drawn from a whole-cartridge tag
  -- search it came out as a black silhouette -- its tag has no palette of its
  -- own in this scene, so the search paired it with one from somewhere else.
  -- Taking it out instead left the rider pedalling thin air.  The scene's own
  -- loader settles it: four 64x32 frames, in the rider's palette, under a
  -- rider whose sheet is the body alone.
  local pedal = math.floor(self.rideX / PEDAL_FRAMES)
  local x = math.floor(self:riderX())
  local rider, riderQuad, _, riderH = self:actor(self:riderName(), pedal)
  local bike, bikeQuad, _, bikeH = self:actor("bike", pedal)
  local top = RIDER_Y - 40
  if bike and bikeQuad then
    -- the wheels sit under the body, not over it
    love.graphics.draw(bike, bikeQuad, x,
                       top + (riderH or 64) - (bikeH or 32))
  end
  if rider and riderQuad then
    love.graphics.draw(rider, riderQuad, x, top)
  end
  return drew
end

-- ---------------------------------------------------------------------------

function Gen3Intro:draw()
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  love.graphics.setColor(1, 1, 1, 1)

  local layers = self:shotLayers()

  if self.frame < T_SCENE_2 then
    if layers then
      self:drawShot(layers)
      self:drawDrops()
      self:drawSparkles()
      self:drawSilhouette()
    end
    local alpha = self:cardAlpha()
    if alpha > 0 or not layers then
      -- with no shot to draw the card over, it is the whole scene, and it
      -- stands for as long as the cartridge's logo does
      self:drawCard(layers and alpha or 1)
    end
    -- scene one goes out to black and scene two comes up out of it
    if self.frame >= T_SCENE_1_END then
      local into = (self.frame - T_SCENE_1_END) / (T_SCENE_2 - T_SCENE_1_END)
      love.graphics.setColor(0, 0, 0, math.min(1, into))
      love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
      love.graphics.setColor(1, 1, 1, 1)
    end
    return
  end

  local drew = self:drawRide()

  local since = self.frame - T_SCENE_2
  if since < FADE_FRAMES then
    love.graphics.setColor(0, 0, 0, 1 - since / FADE_FRAMES)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
    love.graphics.setColor(1, 1, 1, 1)
  end
  local left = T_SCENE_2_END - self.frame
  if drew ~= false and left < FADE_FRAMES then
    love.graphics.setColor(0, 0, 0, 1 - left / FADE_FRAMES)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return Gen3Intro
