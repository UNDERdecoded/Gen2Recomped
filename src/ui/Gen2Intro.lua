-- The Gold/Silver attract movie, ported from pokegold
-- engine/movie/intro.asm (GoldSilverIntro / IntroSceneJumper) and
-- engine/movie/splash.asm (SplashScreen / GameFreakPresents*).
--
-- The original runs 17 scenes over LY overrides, OAM sprite anims and
-- per-scene palette pokes.  The art that survives a ROM rip is the two
-- composed backgrounds (Intro_WaterGFX1/Meta/Tilemap and the grass set,
-- see RomExtractorGen2:gen2IntroBackground), the copyright strip and the
-- GAME FREAK logo, so the port keeps the scene ORDER and timing and
-- rebuilds the motion here: the ocean pans, the meadow pans, and the three
-- starters flash in over it (Intro_ChikoritaAppears / _CyndaquilAppears /
-- _TotodileAppears) before the fade into the title screen.
--
-- Every asset is optional.  A rip that produced none of it still plays the
-- full sequence with the text fallbacks, which is what the headless test
-- drivers see.

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local Music = require("src.core.Music")

local Gen2Intro = {}
Gen2Intro.__index = Gen2Intro
Gen2Intro.isOpaque = true

function Gen2Intro:wantsFillScale() return true end

local function tryImage(entry)
  local path = type(entry) == "table" and entry.path or entry
  if type(path) ~= "string" then return nil end
  local ok, image = pcall(love.graphics.newImage, path)
  return ok and image or nil
end

-- { name, frames }: the beats GoldSilverIntro walks (IntroSceneJumper's
-- seventeen scenes collapsed to the ones that have distinct art), at the
-- original's frame counts.  Scene changes are hard cuts except the fades.
--
--   IntroScene1-2   underwater, hSCX $58, sine LY overrides on rSCY
--   IntroScene3     rise to the surface (hSCY up, hSCX -1 every 4 frames)
--   IntroScene4     at the surface, Lapras drifts left (hSCX -2 / 16)
--   IntroScene5     fade out over five palette steps of 16 frames
--   IntroScene6-7   meadow, hSCX $60 scrolling to 0 one pixel every 4
--   IntroScene8     Pikachu's attack beat ($ff frames)
--   IntroScene9     scroll down and fade, nine palette steps of 8 frames
--   IntroScene11-16 the starters flash in, then Charizard's fireball
--   IntroScene17    64 frame hold into the title screen
-- The first two scenes are the port's own branding and studio cards; they
-- need none of the ripped attract-movie art that follows them.
local GEN2_INTRO_CARD_SCENES = 2
local SCENES = {
  { "brand", 150 },
  { "studio", 180 },
  { "underwater", 128 },
  -- 15 metatile rows of water at one pixel every two frames
  { "rise", 480 },
  { "surface", 240 },
  { "oceanFade", 80 },
  { "meadow", 384 },
  { "meadowHold", 255 },
  { "meadowFade", 72 },
  { "starters", 336 },
  { "fade", 64 },
}

-- The OBJ cast RomExtractorGen2:gen2IntroActors composes, as { frames,
-- sequence, originX, originY }.  `sequence` is the frameset's
-- { frame, duration } steps; `origin` is where the anim struct's own
-- coordinate sits inside the composed image.
local function loadActor(entry)
  if type(entry) ~= "table" or type(entry.frames) ~= "table" then return nil end
  local images = {}
  for index, path in ipairs(entry.frames) do images[index] = tryImage(path) end
  if not images[1] then return nil end
  local sequence = entry.sequence
  if type(sequence) ~= "table" or #sequence == 0 then sequence = { { 1, 1 } } end
  local total = 0
  for _, step in ipairs(sequence) do total = total + (step[2] or 1) end
  return {
    images = images, sequence = sequence, total = math.max(1, total),
    ox = entry.originX or 0, oy = entry.originY or 0,
  }
end

-- (x, y) is where the anim struct sits in SCREEN space -- OAM coordinates
-- carry the hardware's +8 x / +16 y, so the callers below have already
-- taken those off the `depixel` the ROM spawns each object at.
local function drawActor(actor, x, y, age)
  if not actor then return end
  local at = age % actor.total
  for _, step in ipairs(actor.sequence) do
    local duration = step[2] or 1
    if at < duration then
      local image = actor.images[step[1]]
      if image then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(image,
          math.floor(x - actor.ox), math.floor(y - actor.oy))
      end
      return
    end
    at = at - duration
  end
end

-- Intro_InitShellders: three `depixel`s on the sea floor.  As the camera
-- rises IntroScene3_ScrollToSurface walks wGlobalAnimYOffset up in step
-- with hSCY, so they slide down the screen and AnimSeq_GSIntroShellder
-- drops each one once it passes OAM y $b0.
local SHELLDERS = { { 48, 128 }, { 72, 96 }, { 112, 112 } }

-- Intro_InitMagikarps alternates two triples every 64 frames
-- (`wIntroFrameCounter2 and $3f` / `and $40`).  These stay in OAM
-- coordinates because the leap relies on the byte wrap.
local MAGIKARPS = {
  { { 224, 232 }, { 0, 208 }, { 192, 0 } },
  { { 240, 224 }, { 192, 248 }, { 224, 16 } },
}
local MAGIKARP_LIFE = 64

-- Intro_InitSineLYOverrides seeds wLYOverrides2 with a sine and
-- Intro_UpdateLYOverrides rotates it one entry per frame, writing rSCY per
-- scanline (hLCDCPointer = $42).  Lines 0-15 stay flat -- loop1 writes a
-- plain hSCY for the first $10 of them.
local WOBBLE_FLAT_LINES = 16
local WOBBLE_PERIOD = 64
local WOBBLE_AMPLITUDE = 6

local STARTER_FRAMES = 112   -- per mon: silhouette, flash, colour

function Gen2Intro.new(game, onDone)
  local self = setmetatable({}, Gen2Intro)
  self.game = game
  self.onDone = onDone
  self.finished = false
  self.scene = 1
  self.timer = 0
  -- the ROM keeps hSCX/hSCY across scenes; so does the port
  self.scx = 0x58
  self.scy = 0

  local intro = (game.data.field and game.data.field.intro) or {}
  self.cfg = intro
  self.skipAll = intro.skip and true or false
  -- Branding replaces the Nintendo copyright card and the GAME FREAK
  -- splash outright, so the ripped art for both is deliberately not drawn.
  local studio = intro.studio or {}
  self.brand = studio.card or studio.credit or "UNDERdecodedHD"
  self.brandYear = studio.year or "2026"
  self.stars = tryImage(intro.stars)
  self.water = tryImage(intro.water)
  self.grass = tryImage(intro.grass)
  -- Scenes 1-2 are the branding and studio cards, which the port draws itself
  -- and which need no ripped art.  Everything after them in SCENES is the
  -- Gold/Silver attract movie, built from Intro_WaterGFX1 / Intro_GrassGFX1.
  -- With neither backdrop present those scenes drew whatever was left in the
  -- tile cache, so the list stops after the cards instead.
  --
  -- Crystal ships a different movie entirely (CrystalIntro's 28-scene Unown
  -- and Suicune sequence), so the importer hands over its own scene list:
  -- one composed screen per beat, with the frame budget the ROM holds it for.
  -- The two branding cards still come first -- they are the port's own.
  self.scenes = SCENES
  if intro.layout == "crystal" and type(intro.scenes) == "table"
      and intro.scenes[1] then
    local list = { SCENES[1], SCENES[2] }
    self.crystal = {}
    for _, entry in ipairs(intro.scenes) do
      list[#list + 1] = { "crystal", entry.frames or 64 }
      self.crystal[#list] = {
        image = tryImage(entry.image),
        mode = entry.mode,
        scroll = entry.scroll,
        actors = entry.actors,
      }
    end
    self.scenes = list
    self.ramps = intro.ramps or {}
  end
  self.lastScene = #self.scenes
  if self.scenes == SCENES and not (self.water or self.grass) then
    self.lastScene = GEN2_INTRO_CARD_SCENES
  end
  -- Intro_WaterTilemap is 32 metatile rows and IntroScene1 starts the
  -- camera 15 of them down, so the rise has somewhere to rise FROM.
  self.waterStartY = intro.waterStartY or 0
  self.animY = 0
  self.actors = {}
  for name, entry in pairs(intro.actors or {}) do
    self.actors[name] = loadActor(entry)
  end

  self.starters = {}
  local Sprites = require("src.pokemon.Sprites")
  local ImageWriter = require("src.import.ImageWriter")
  for index, species in ipairs(intro.starters or {}) do
    local ok, path = pcall(Sprites.path, game.data, species, "front")
    if ok and path then
      -- the mon sheets are stored on an opaque white field; the intro puts
      -- them over the meadow, so knock the surround out
      local okImage, image = pcall(function()
        return love.graphics.newImage(
          ImageWriter.matteColor0(love.image.newImageData(path)))
      end)
      self.starters[index] = okImage and image or nil
    end
  end
  return self
end

function Gen2Intro:enter()
  if self.skipAll then
    self:finish()
    return
  end
  local data = self.game.data
  local song = self.cfg.music or "Music_TitleScreen"
  if data.audio and data.audio.songs and data.audio.songs[song] then
    pcall(Music.play, data, song)
  end
end

function Gen2Intro:finish()
  if self.finished then return end
  self.finished = true
  pcall(Music.stop)
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

function Gen2Intro:update(dt)
  if self.finished then return end
  local input = self.game.input
  if input and (input:wasPressed("start") or input:wasPressed("a")
                or input:wasPressed("b")) then
    self:finish()
    return
  end
  self.timer = self.timer + 1
  self:advanceCamera()
  local scene = self.scenes[self.scene]
  if not scene or self.timer >= scene[2] then
    self.scene = self.scene + 1
    self.timer = 0
    self:enterScene()
    if self.scene > (self.lastScene or #self.scenes) then self:finish() end
  end
end

-- hSCX / hSCY as each scene's setup leaves them (IntroScene1 and
-- IntroScene6 both DisableLCD and reseed the camera).
function Gen2Intro:enterScene()
  local scene = self.scenes[self.scene]
  local name = scene and scene[1]
  if name == "underwater" then
    self.scx, self.scy = 0x58, self.waterStartY
    self.animY = 0
  elseif name == "meadow" then
    self.scx, self.scy = 0x60, 0
  elseif name == "starters" then
    self.scx, self.scy = 0, 0
  end
end

function Gen2Intro:advanceCamera()
  local scene = self.scenes[self.scene]
  local name = scene and scene[1]
  if name == "rise" then
    -- IntroScene3_ScrollToSurface: hSCX every 4 frames, hSCY every 2, and
    -- wGlobalAnimYOffset climbs with hSCY so the OBJs ride the water
    if self.timer % 4 == 0 then self.scx = self.scx - 1 end
    if self.timer % 2 == 0 and self.scy > 0 then
      self.scy = self.scy - 1
      self.animY = self.animY + 1
    end
  elseif name == "surface" or name == "oceanFade" then
    if self.timer % 16 == 0 then self.scx = self.scx - 2 end
  elseif name == "meadow" then
    if self.timer % 4 == 0 and self.scx > 0 then self.scx = self.scx - 1 end
  elseif name == "meadowFade" then
    self.scy = self.scy + 1
  end
end

-- A 256x256 backdrop read the way the PPU reads the BG map: screen line L
-- shows BG row hSCY + L, wrapped on both axes so the camera can run
-- anywhere.  Two reusable quads keep the per-scanline path allocation free.
local bandLeft, bandRight

-- `height` rows starting at source row sy (already wrapped, and no taller
-- than the image allows) copied to screen row dy.
local function drawBand(image, sx, sy, dy, height)
  local w, h = image:getDimensions()
  bandLeft = bandLeft or love.graphics.newQuad(0, 0, 1, 1, w, h)
  bandRight = bandRight or love.graphics.newQuad(0, 0, 1, 1, w, h)
  local first = math.min(160, w - sx)
  bandLeft:setViewport(sx, sy, first, height, w, h)
  love.graphics.draw(image, bandLeft, 0, dy)
  if first < 160 then
    bandRight:setViewport(0, sy, 160 - first, height, w, h)
    love.graphics.draw(image, bandRight, first, dy)
  end
end

-- `wobble(line)` is the extra rSCY the LY overrides add on that scanline.
local function drawScrolled(image, scx, scy, wobble)
  local w, h = image:getDimensions()
  local sx = scx % w
  if not wobble then
    local sy = scy % h
    local first = math.min(144, h - sy)
    drawBand(image, sx, sy, 0, first)
    if first < 144 then drawBand(image, sx, 0, first, 144 - first) end
    return
  end
  for line = 0, 143 do
    drawBand(image, sx, (scy + line + wobble(line)) % h, line, 1)
  end
end

function Gen2Intro:wobbleAt(line)
  if line < WOBBLE_FLAT_LINES then return 0 end
  local phase = (line - WOBBLE_FLAT_LINES + self.timer) / WOBBLE_PERIOD
  return math.floor(WOBBLE_AMPLITUDE * math.sin(phase * 2 * math.pi) + 0.5)
end

-- The fades are DmgToCgbBGPals palette ramps that end on %00000000, which
-- is every shade mapped to colour 0 -- white.
local function drawFade(alpha)
  if alpha <= 0 then return end
  love.graphics.setColor(1, 1, 1, math.min(1, alpha))
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(1, 1, 1, 1)
end

local function centered(text, y)
  Font.draw(text, math.floor((160 - #text * 8) / 2), y)
end

function Gen2Intro:drawBrand(withStar)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  if withStar and self.stars then
    -- GameFreakPresents_LogoSparkles: a star crosses before the wordmark
    local sw, sh = self.stars:getDimensions()
    local frame = math.floor(self.timer / 6) % math.max(1, sw / 8)
    local travel = math.min(1, self.timer / 90)
    love.graphics.draw(self.stars,
      love.graphics.newQuad(frame * 8, 0, 8, sh, sw, sh),
      math.floor(40 + travel * 80), 48)
  end
  love.graphics.setColor(0, 0, 0, 1)
  centered(Strings(self.brand), 64)
  centered(Strings(self.brandYear), 80)
  love.graphics.setColor(1, 1, 1, 1)
end

function Gen2Intro:drawOcean(wobble)
  love.graphics.setColor(1, 1, 1, 1)
  if self.water then
    drawScrolled(self.water, self.scx, self.scy,
      wobble and function(line) return self:wobbleAt(line) end or nil)
  else
    love.graphics.setColor(0.16, 0.31, 0.78, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

function Gen2Intro:drawMeadow()
  love.graphics.setColor(1, 1, 1, 1)
  if self.grass then
    drawScrolled(self.grass, self.scx, self.scy, nil)
  else
    love.graphics.setColor(0.20, 0.55, 0.24, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

-- Shellder / Magikarp / Lapras.  Everything on the water is anchored to
-- wGlobalAnimYOffset (self.animY), which climbs in step with the rising
-- camera, so the cast scrolls with the sea instead of sticking to the LCD.
function Gen2Intro:drawOceanActors(name)
  if name == "underwater" or name == "rise" then
    for _, spot in ipairs(SHELLDERS) do
      local y = spot[2] + self.animY
      -- AnimSeq_GSIntroShellder drops one once it passes OAM y $b0
      if y < 160 then
        drawActor(self.actors.shellder, spot[1], y, self.timer)
      end
    end
  end
  if name == "rise" then
    local wave = math.floor(self.timer / MAGIKARP_LIFE)
    local age = self.timer % MAGIKARP_LIFE
    for _, spot in ipairs(MAGIKARPS[wave % 2 + 1]) do
      -- OAM space, so the +4 x per frame wraps the way the hardware does
      local x = (spot[1] + age * 4) % 256 - 8
      local y = (spot[2] + self.animY) % 256 - 16
      if x <= 160 and y > -16 and y < 144 then
        drawActor(self.actors.magikarp, x, y, age)
      end
    end
  end
  if name == "surface" or name == "oceanFade" then
    -- AnimSeq_GSIntroLapras drifts in from the right to OAM x $58, holds
    -- $b0 frames, then carries on off the left edge
    local travel = name == "surface" and self.timer or (240 + self.timer)
    local x = 184 - math.min(travel, 104)
    if travel > 280 then x = 80 - (travel - 280) end
    local y = 112 + math.floor(math.sin(travel / 16) * 1.5)
    drawActor(self.actors.lapras, x, y, travel)
  end
end

-- Jigglypuff sings, the notes drift off, then Pikachu runs in from the
-- right (Intro_InitPikachu's `depixel 14, 24`) and both bolt left.
function Gen2Intro:drawMeadowActors(name)
  local jiggly, pikachu = 40, 184
  local age = self.timer
  if name == "meadow" then
    pikachu = math.max(120, 184 - self.timer)
    -- Intro_InitNote spawns one every 64 frames while Jigglypuff sings
    for wave = 0, math.min(5, math.floor(self.timer / 64)) do
      local at = self.timer - wave * 64
      if at >= 0 and at < 64 then
        drawActor(self.actors.note, 40 + math.floor(at / 2),
          76 - math.floor(at / 2), at)
      end
    end
  elseif name == "meadowHold" or name == "meadowFade" then
    pikachu = 120
    if self.timer > 64 then
      local run = self.timer - 64
      jiggly = 40 - run * 2
      pikachu = math.max(72, 120 - run)
      if run > 96 then pikachu = 72 - (run - 96) * 2 end
    end
  else
    return
  end
  if jiggly > -32 then
    drawActor(self.actors.jigglypuff, jiggly, 96, age)
  end
  if pikachu > -48 then
    drawActor(self.actors.pikachuTail, pikachu, 96, age)
    drawActor(self.actors.pikachu, pikachu, 96, age)
  end
end

-- IntroScene11's hSCY jumptable: each starter loads its palette, appears as
-- a black silhouette (Intro_FlashSilhouette), flashes
-- (Intro_FlashMonPalette) and then holds in colour before the next.
function Gen2Intro:drawStarters()
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(1, 1, 1, 1)
  local slot = math.min(3, math.floor(self.timer / STARTER_FRAMES) + 1)
  local sprite = self.starters[slot]
  if not sprite then return end
  local phase = self.timer % STARTER_FRAMES
  local w, h = sprite:getDimensions()
  local x, y = math.floor((160 - w) / 2), math.floor((144 - h) / 2)
  if phase < 24 then
    -- silhouette: every shade forced to the darkest entry
    love.graphics.setColor(0, 0, 0, 1)
  elseif phase < 48 and math.floor((phase - 24) / 4) % 2 == 0 then
    love.graphics.setColor(1, 1, 1, 1)
  else
    love.graphics.setColor(1, 1, 1, 1)
  end
  love.graphics.draw(sprite, x, y)
  love.graphics.setColor(1, 1, 1, 1)
end

-- One composed screen per beat.  A "pulse" screen is the Unown eyes: the ROM
-- blacks every BG palette and relights ONE, walking colours 1-3 up the
-- BWFade / BlackLBlueFade / BlackBlueFade ramps against a triangle counter
-- (CrystalIntro_UnownFade, 39:$5223).  The screen is stored as a
-- white-on-black mask, so multiplying it by the ramp colour reproduces that:
-- black stays black, and the eyes rise out of it and fall back.
--
-- [$CF65] & $3F mirrored about $1F is the triangle -- two full pulses across
-- a 128 frame hold.
local CRYSTAL_PULSE_PERIOD = 0x40
local CRYSTAL_PULSE_HALF = 0x1F

function Gen2Intro:drawCrystalScene()
  local scene = self.crystal and self.crystal[self.scene]
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  if not (scene and scene.image) then return end
  local r, g, b = 1, 1, 1
  if scene.mode == "pulse" then
    local ramp = self.ramps and self.ramps.bw
    local step = self.timer % CRYSTAL_PULSE_PERIOD
    if step > CRYSTAL_PULSE_HALF then
      step = (CRYSTAL_PULSE_PERIOD - 1) - step
    end
    local color = ramp and ramp[step + 1]
    if color then
      r, g, b = color[1], color[2], color[3]
    else
      local level = step / CRYSTAL_PULSE_HALF
      r, g, b = level, level, level
    end
  end
  love.graphics.setColor(r, g, b, 1)
  -- The screen is the whole 256px BG map row; hSCX picks the 160px window and
  -- wraps, exactly as the PPU reads it.  IntroScene14 subtracts 10 from hSCX
  -- every frame (the forest tearing past) and IntroScene18 adds 8 until it
  -- reaches $60 and then holds (the camera settling on Suicune's face).
  local width = scene.image:getWidth()
  local scrollX = 0
  local scroll = scene.scroll
  if scroll then
    scrollX = (scroll.from or 0) + (scroll.step or 0) * self.timer
    if scroll.to then
      if (scroll.step or 0) >= 0 then scrollX = math.min(scrollX, scroll.to)
      else scrollX = math.max(scrollX, scroll.to) end
    end
    scrollX = math.floor(scrollX) % width
  end
  local quad = love.graphics.newQuad(scrollX, 0, 160, 144, width, 144)
  love.graphics.draw(scene.image, quad, 0, 0)
  if scrollX + 160 > width then
    -- the window straddles the wrap, so the leading edge comes from the start
    local shown = width - scrollX
    love.graphics.draw(scene.image,
      love.graphics.newQuad(0, 0, 160 - shown, 144, width, 144), shown, 0)
  end
  love.graphics.setColor(1, 1, 1, 1)
  for _, motion in ipairs(scene.actors or {}) do
    self:drawCrystalActor(motion)
  end
end

-- Suicune crossing the forest.  The scene handler holds its x still for
-- `hold` frames, then walks it down by `step` a frame; IntroScene14 switches
-- to a faster `step2` once the jump sound fires at `step2At`, and takes the
-- sprite off screen entirely below `hideBelow`.  x and y are the pixel
-- coordinates InitSpriteAnimStruct was handed, so they need no OAM fudge.
--
-- SpriteAnimFunc_IntroPichuWooper steps a phase field by 2 up to $14 and puts
-- AnimSeqs_Sine of the NEGATED phase, amplitude $20, into the sprite's y
-- offset -- so Wooper and Pichu rise about 30px out of the grass over ten
-- frames and then stay put, which is why the ROM spawns them at y 176 and
-- 169, both below the screen.
local HOP_STEP = 2
local HOP_LIMIT = 0x14
local HOP_AMPLITUDE = 0x20

local function hopOffset(age)
  local phase = math.min(HOP_LIMIT, math.max(0, age) * HOP_STEP)
  -- Sprites_Sine is d * sin(a * pi / 32); the phase is negated, so the offset
  -- is upward
  return -math.floor(HOP_AMPLITUDE * math.sin(phase * math.pi / 32) + 0.5)
end

function Gen2Intro:drawCrystalActor(motion)
  if not motion then return end
  local actor = self.actors and self.actors[motion.name]
  if not actor then return end
  local spawn = motion.spawn or 0
  if self.timer < spawn then return end
  local age = self.timer - spawn
  local x, y = motion.x or 0, motion.y or 0
  if motion.hop then
    y = y + hopOffset(age)
  else
    local elapsed = self.timer - (motion.hold or 0)
    if elapsed > 0 then
      if motion.step2At and self.timer >= motion.step2At then
        local first = motion.step2At - (motion.hold or 0)
        x = x + (motion.step or 0) * first
          + (motion.step2 or 0) * (self.timer - motion.step2At)
      else
        x = x + (motion.step or 0) * elapsed
      end
    end
    if motion.hideBelow and x < motion.hideBelow then return end
  end
  drawActor(actor, x, y, age)
end

function Gen2Intro:draw()
  -- the scenes are ripped in CGB color; keep the SGB palette pass off them
  pcall(function() require("src.render.PaletteFX").markTrueColor(0, 0, 160, 144) end)
  local scene = self.scenes[self.scene]
  local name = scene and scene[1] or "fade"
  local length = scene and scene[2] or 64
  if name == "crystal" then
    self:drawCrystalScene()
    return
  end
  if name == "brand" then
    self:drawBrand(false)
  elseif name == "studio" then
    self:drawBrand(true)
  elseif name == "underwater" then
    self:drawOcean(true)
    self:drawOceanActors(name)
  elseif name == "rise" then
    self:drawOcean(true)
    self:drawOceanActors(name)
  elseif name == "surface" then
    self:drawOcean(false)
    self:drawOceanActors(name)
  elseif name == "oceanFade" then
    self:drawOcean(false)
    self:drawOceanActors(name)
    drawFade(self.timer / length)
  elseif name == "meadow" or name == "meadowHold" then
    self:drawMeadow()
    self:drawMeadowActors(name)
  elseif name == "meadowFade" then
    self:drawMeadow()
    self:drawMeadowActors(name)
    drawFade(self.timer / length)
  elseif name == "starters" then
    self:drawStarters()
  else
    self:drawStarters()
    drawFade(self.timer / length)
  end
end

return Gen2Intro
