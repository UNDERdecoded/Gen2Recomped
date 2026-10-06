-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- What a NEW GAME on Platinum actually opens with: a television broadcast,
-- then Professor Rowan.
--
-- Until now NEW GAME went straight to the bedroom, because `boot.screens.
-- newGame` was `false` -- OakSpeech replays a professor's intro out of text
-- Platinum does not have, and there was nothing else to put there.  There is
-- now: the `intro` stage extracts both scenes and both scripts, and this plays
-- them.
--
-- THE TELEVISION FIRST.  `RowanIntroTv` is its own application on the
-- cartridge and it runs before Rowan's: a news report about the professor
-- returning to Sinnoh, drawn as three background layers -- the broadcast, a
-- scanline overlay and the set's bezel -- with one line of text under it.
--
-- THEN ROWAN, over five backdrops and ten figures, of which this plays the
-- main line: the greeting, who you are, your name, your friend's name, and the
-- send-off.  The CONTROL INFO and ADVENTURE INFO lectures are extracted and
-- NOT offered here -- they are a menu of tutorials about a touch screen and a
-- +Control Pad this port does not have, and a lecture that describes hardware
-- the player is not holding is worse than one they never saw.  `gen4_intro`
-- carries both so a mod can put them back.
--
-- TWO SCENES ARE NOT WORDS, and both were reported missing from play.
--
--   * THE POKE BALL.  "in the intro rowan isnt thorwing out a pokemon like he
--     does in the rom".  He does: the ball's button is pushed in over three
--     pieces of art, the screen flashes four times, and a BUNEARY -- the
--     species' own battle front sprite, already in this cache -- rises out of
--     it on a parabola, hops right, hops left and settles.  Every number in
--     that sentence is below, taken from the app's own arithmetic.
--   * THE GENDER CHOICE.  "the players sprites when selecting boy or girl
--     arent animated like they should be".  Both avatars stand on screen at
--     once and THE ONE YOU ARE POINTING AT IS RUNNING -- the four "poses"
--     `Gen4IntroScene` extracts as boy_1..boy_4 and girl_1..girl_4 are a
--     four-frame run cycle, so nothing had to be added to the cache to play
--     it.  The other one holds still and is dimmed.
--
-- PAGE BREAKS ARE IN THE TEXT ALREADY.  Gen 4 writes 0x25BC for "wait, then
-- clear" and 0x25BD for "wait, then scroll", and the decoder renders them as
-- CR and FF -- so a page is a split on those characters rather than something
-- this file has to count.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Screens = require("src.ui.Screens")
local Sprites = require("src.pokemon.Sprites")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen4RowanIntro = {}
Gen4RowanIntro.__index = Gen4RowanIntro
Gen4RowanIntro.isOpaque = true

local W, H = 256, 192

-- PLATINUM'S OWN MESSAGE BOX, and it used to be a hand-placed rectangle.
--
-- The cartridge's dialogue window is (2, 19) 27x4 tiles -- the TEXT INTERIOR --
-- with DrawMessageBoxFrame reaching two tiles left, three right, one row above
-- and one below, so the box is the full 32-tile width at rows 18..23.  This is
-- that rect in the port's convention (interior plus one tile of border), which
-- is what Font.drawDialogueBox expands.  `{ 0, 16, 32, 8 }` was two rows too
-- tall and, once the frame reader was fixed to reach past its rect, one tile
-- off the screen on each side.
local BOX = { tx = 1, ty = 18, tw = 29, th = 6 }
-- The interior's own origin, and two lines of sixteen: FONT_MESSAGE is
-- maxLetterHeight 16 with lineSpacing 0, and a four-tile window is 32 tall.
local TEXT_X = 16
local TEXT_Y = 152
local LINE_H = 16

-- ---------------------------------------------------------------------------
-- The release, in the numbers the cartridge uses
-- ---------------------------------------------------------------------------

-- The push-in: the app loads the next tile sheet, sets `animDelayUpdateCounter`
-- to 4 and decrements it once a frame before the next load, so each picture is
-- on screen for five frames.
local BALL_FRAME_HOLD = 5

-- How many of them there are.  Spelled out rather than taken from the cache,
-- because a cache written before the ball was extracted would otherwise report
-- zero and skip the push-in silently; and spelled out rather than borrowed from
-- some other table that happens to have three entries, which is an invariant
-- that is almost true.  It is `#Gen4IntroScene.BALL.frames`.
local BALL_PICTURES = 3

-- THE FLASH IS FOUR BRIGHTNESS RAMPS, not "it goes white".
-- `BrightnessController_StartTransition(stepCount, target, start, ...)` -- the
-- TARGET comes before the START, which is exactly the kind of argument order a
-- reader assumes and gets backwards -- is called with (1, 16, 0), (1, 0, 16),
-- (4, 16, 0), and then (16, 0, 16) as the Pokemon spawns.  16 is full white and
-- a step is a frame: white in one frame, out in one, in over four, and out over
-- sixteen WHILE the Pokemon is already on screen.
local BALL_FLASHES = {
  { steps = 1, from = 0,  to = 16 },
  { steps = 1, from = 16, to = 0 },
  { steps = 4, from = 0,  to = 16 },
}
local BALL_SPAWN_FLASH = { steps = 16, from = 16, to = 0 }
local FLASH_MAX = 16

-- IT IS A BUNEARY.  `RowanIntro_LoadBunearySprite` builds an ordinary
-- PokemonSpriteTemplate for SPECIES_BUNEARY, FACE_FRONT, so the picture is the
-- species' own front sprite out of pl_pokegra rather than anything stored in
-- the intro archive -- which is why this needs no new art.
local MON_SPECIES = 427

-- Where it sits: `Bg_LoadToTilemapRect(..., 11, 9, 10, 10)`, a 10x10-tile
-- (80x80) picture with its top-left at tile (11, 9) of the main screen.
local MON_X, MON_Y, MON_SIZE = 11 * 8, 9 * 8, 10 * 8

-- The release glow.  The sprite's palette is blended toward 0x6a3c -- BGR555
-- (28, 17, 26), a pink-white -- with weight `counter / 3` out of 16, counting
-- down from 48.  So it is a solid silhouette for the first three frames and has
-- its own colours back after forty-eight.  The flash's plane mask is
-- BG0|BG1|BG3 and the Pokemon is on BG2, so this blend is the ONLY thing
-- whitening it: the flash deliberately leaves it alone.
local GLOW = { 28 / 31, 17 / 31, 26 / 31 }
local GLOW_FRAMES, GLOW_DIVISOR = 48, 3

-- THE ARC, as the app computes it rather than as a curve that looks similar.
-- Each phase is a parabola in its own frame counter,
--
--     y = base + coeff * 9 * t - floor(9 * t * t / divisor)
--
-- in INTEGER arithmetic, and a phase ends the first frame y comes back down to
-- zero having been positive.  The rise is halved and clamped before it is used
-- (`newYOffset >> 1`, capped at 8 * 18); the two hops are not.
--
-- A BACKGROUND OFFSET IS NOT A POSITION.  The hardware scrolls the view, so a
-- larger offset moves the picture UP: every reader below is `MON_Y - offset`.
local ARC = {
  { base = -8 * 13, coeff = 9, divisor = 2, dx =  1, half = true, cap = 8 * 18 },
  { base = 0,       coeff = 3, divisor = 3, dx = -2 },
  { base = 0,       coeff = 3, divisor = 3, dx =  4 },
}

-- THE PORT HAS ONE SCREEN AND THE CARTRIDGE HAS TWO, and this is where that
-- costs something.  Before the arc above, the app spends three frames moving a
-- SECOND copy of the Pokemon up the BOTTOM screen; the arc then plays on the
-- top one, starting from below its own screen.  On hardware that reads as one
-- continuous rise across the gap between the screens.  On one screen it is the
-- same motion twice -- the Pokemon would leave upward and then re-enter from
-- below -- so only those three frames' horizontal drift is kept, and the arc,
-- which already begins off the bottom, is the whole of what is played.
local RISE_DRIFT = 6

local SETTLE_FRAMES, GAP_FRAMES = 40, 30

-- Every layer fade in this app is sixteen frames: the blend alpha walks 0 to 16
-- or 16 to 0, one step per frame.
local FADE_FRAMES = 16

-- ---------------------------------------------------------------------------
-- The gender choice
-- ---------------------------------------------------------------------------

-- `RowanIntro_AnimateAvatarRun` cycles the SELECTED side through intro members
-- 9, 10, 11, 12 (boy) or 14, 15, 16, 17 (girl), which is precisely
-- Gen4IntroScene's boy_1..boy_4 and girl_1..girl_4.
local RUN = {
  boy  = { "boy_1", "boy_2", "boy_3", "boy_4" },
  girl = { "girl_1", "girl_2", "girl_3", "girl_4" },
}
local RUN_HOLD = 5                -- counter = 4, decremented before the swap
local DIM = 6 / 16                -- G2_SetBlendAlpha(..., 6, 10)

-- The boy's layer is offset -48 and the girl's +48, and an offset moves the
-- picture the other way -- so the boy stands 48 pixels RIGHT of centre and the
-- girl 48 LEFT.  On confirm the chosen one slides back four pixels a frame.
local SPREAD = 8 * 6
local CENTRE_STEP = 4

function Gen4RowanIntro:uiSize() return W, H end
function Gen4RowanIntro:wantsFillScale() return true end
function Gen4RowanIntro:wantsEdgeBleed() return false end

function Gen4RowanIntro:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function Gen4RowanIntro.new(game, onDone)
  local self = setmetatable({}, Gen4RowanIntro)
  self.game = game
  self.onDone = onDone
  self.cache = {}
  self.rec = (game.data and game.data.gen4_intro) or nil
  self.answers = { gender = "boy" }
  self.blink = 0

  if not self.rec then
    -- A cache from before the intro stage.  Finishing immediately is the same
    -- behaviour NEW GAME had before this screen existed, which is a playable
    -- game rather than a blank screen nobody can get out of.
    Logger.warn("gen4 intro: this cache carries no `gen4_intro` record; "
                .. "skipping the opening")
    self.finished = true
    return self
  end

  self.phase = "tv"
  self.pages = self:pagesOf(self.rec.text and self.rec.text.tv)
  self.page = 1
  self.step = 0
  return self
end

-- ------------------------------------------------------------------ text --

-- Split a decoded Gen 4 string into pages.  CR is the cartridge's "wait, then
-- clear" and FF its "wait, then scroll"; both end a page as far as a reader is
-- concerned, and neither is a character to draw.
function Gen4RowanIntro:pagesOf(text)
  if type(text) ~= "string" or text == "" then return { "" } end
  text = self:fill(text)
  local pages = {}
  -- "\v" and "\f" are the two waits the cartridge writes -- scroll-and-wait
  -- and clear-and-wait.  This screen puts its words up a page at a time, so
  -- both are a page break here.  ("\v" was "\r" until the decoder was
  -- corrected; see Gen4Text.)
  for page in (text .. "\v"):gmatch("([^\v\f]*)[\v\f]") do
    page = page:gsub("^%s+", ""):gsub("%s+$", "")
    if page ~= "" then pages[#pages + 1] = page end
  end
  if #pages == 0 then pages[1] = "" end
  return pages
end

-- Substitute the two names the script asks for and drop the control codes
-- this screen does not act on.  `{STRVAR_1 3 0 0}` is the player and
-- `{STRVAR_1 3 1 0}` the rival -- the middle number is the variable slot, and
-- it is the only part that distinguishes them.
function Gen4RowanIntro:fill(text)
  local player = self.answers.name or Strings("PLAYER")
  local rival = self.answers.rival or Strings("RIVAL")
  text = text:gsub("{STRVAR_1 %d+ (%d+) %d+}", function(slot)
    return (slot == "1") and rival or player
  end)
  -- {YESNO 0} arms the cartridge's own yes/no box; this screen puts its
  -- question up itself, so the marker is not a word to print.
  text = text:gsub("{YESNO %d+}", "")
  text = text:gsub("{COLOR %d+}", "")
  return text
end

-- ---------------------------------------------------------------- pictures --

function Gen4RowanIntro:img(entry)
  local path = type(entry) == "table" and entry.path or entry
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, image = pcall(Assets.image, path)
    self.cache[path] = ok and image or false
    if self.cache[path] then
      self.cache[path]:setFilter("nearest", "nearest")
    end
  end
  return self.cache[path] or nil
end

function Gen4RowanIntro:backdrop(role)
  return self:img((self.rec.backdrops or {})[role])
end

function Gen4RowanIntro:figure(name)
  return self:img((self.rec.figures or {})[name])
end

-- ------------------------------------------------------------------ flow --

function Gen4RowanIntro:currentStep()
  return (self.rec.script or {})[self.step]
end

function Gen4RowanIntro:beginStep(n)
  self.step = n
  local step = self:currentStep()
  if not step then return self:finish() end
  self.pages = self:pagesOf((self.rec.text or {})[step.text])
  self.page = 1
  -- A step that is a SCENE and not just words.  The ball is on screen while its
  -- line is read -- the app fades it in before the text -- so the state is armed
  -- here and only starts moving when the last page is confirmed.
  if step.scene == "ball" then
    self.ball = { stage = "wait", frame = 1, hold = 0, t = 0, flash = 1 }
  end
end

-- A page turned, or the step's question asked once its last page is read.
function Gen4RowanIntro:advance()
  if self.phase == "tv" then
    if self.page < #self.pages then
      self.page = self.page + 1
      return
    end
    self.phase = "rowan"
    return self:beginStep(1)
  end

  if self.page < #self.pages then
    self.page = self.page + 1
    return
  end
  local step = self:currentStep()
  -- The ball's line has been read: push the button in.  The script does NOT
  -- advance here -- the release plays on this step and the next line, "they
  -- live alongside us", is the step after it.
  if self.ball and self.ball.stage == "wait" then
    self.ball.stage = "push"
    return
  end
  -- ...and that next line has now been read with the Pokemon still standing
  -- there, so this is where it is put away.
  if self.mon and not self.putaway then
    self.putaway = { t = 0 }
    return
  end
  if step and step.ask == "gender" and not self.answers.genderPicked then
    self.phase = "gender"
    self.gender = self:newGenderState()
    return
  end
  if step and step.ask == "name" and not self.answers.name then
    return self:askName()
  end
  if step and step.ask == "rivalName" and not self.answers.rival then
    return self:askRivalName()
  end
  self:beginStep(self.step + 1)
end

function Gen4RowanIntro:askName()
  local boot = self.game.data.field and self.game.data.field.boot
  local presets = (boot and boot.namePresets and boot.namePresets.player) or nil
  if not presets or #presets == 0 then
    presets = { self.answers.gender == "girl" and "Dawn" or "Lucas" }
  end
  local maxLen = (self.game.data.constants or {}).playerNameLength or 7
  Screens.push(self.game, "NamingScreen", {
    title = self:fill((self.rec.text or {}).name or Strings("YOUR NAME?")),
    kind = "player", female = self.answers.gender == "girl",
    presets = presets,
    maxLen = maxLen,
    onDone = function(name)
      self.answers.name = name
      local save = self.game.save
      if save and save.player then save.player.name = name end
      -- The confirmation line has the placeholder in it, so it only reads
      -- correctly once the name is set -- which it now is.
      self:say(self.answers.gender == "girl" and "confirmNameFemale"
               or "confirmNameMale")
    end,
  })
end

function Gen4RowanIntro:askRivalName()
  local presets = {}
  for _, row in ipairs(self.rec.rivalNames or {}) do
    -- The first entry is "New name!", the prompt to type one rather than a
    -- name to offer; the naming screen already has that as its own path.
    if not row.custom and row.label then presets[#presets + 1] = row.label end
  end
  local maxLen = (self.game.data.constants or {}).playerNameLength or 7
  Screens.push(self.game, "NamingScreen", {
    title = self:fill((self.rec.text or {}).rivalName or Strings("RIVAL")),
    kind = "rival",
    presets = presets,
    maxLen = maxLen,
    onDone = function(name)
      self.answers.rival = name
      local save = self.game.save
      if save and save.player then save.player.rival = name end
      self:say("confirmRivalName")
    end,
  })
end

-- Put one line up out of turn -- a confirmation the script does not have a
-- step for -- and carry on from the step after the current one when it is read.
function Gen4RowanIntro:say(key)
  self.pages = self:pagesOf((self.rec.text or {})[key])
  self.page = 1
  self.sayThenAdvance = true
end

function Gen4RowanIntro:chooseGender(which)
  self.answers.gender = which
  self.answers.genderPicked = true
  local save = self.game.save
  if save and save.player then save.player.gender = which end
  -- ...AND THE CHARACTER ALREADY STANDING ON THE MAP.  New Game pushes the
  -- overworld first and this screen on top of it, so the Player object exists
  -- and has already chosen its sheets.  Writing the answer to the save changes
  -- what the NEXT one would wear and nothing about this one, which is how a
  -- player who picked the girl walked out of the bedroom as the boy.
  local overworld = self.game.overworld
  local avatar = overworld and overworld.player
  if avatar and avatar.refreshForm then
    pcall(function() avatar:refreshForm(self.game.data) end)
  end
  self.phase = "rowan"
  self.gender = nil
  self:beginStep(self.step + 1)
end

-- ------------------------------------------------------------- the release --

-- A brightness ramp's value at frame `t`, in the app's own 0..16.
local function ramp(spec, t)
  if t >= spec.steps then return spec.to end
  return spec.from + (spec.to - spec.from) * t / spec.steps
end

-- How white the screen is right now, 0..1.  Nil when nothing is flashing, so
-- the caller does not paint a transparent rectangle every frame of the game.
function Gen4RowanIntro:flash()
  local b = self.ball
  if not b then return nil end
  if b.stage == "flash" then
    return ramp(BALL_FLASHES[b.flash] or BALL_FLASHES[#BALL_FLASHES], b.t)
      / FLASH_MAX
  end
  if b.stage == "spawn" then
    return ramp(BALL_SPAWN_FLASH, b.t) / FLASH_MAX
  end
  return nil
end

-- One frame of the parabola.  Returns true when the last phase has finished.
function Gen4RowanIntro:tickArc()
  local m = self.mon
  local spec = ARC[m.phase]
  if not spec then return true end
  local y = spec.base + spec.coeff * 9 * m.t
            - math.floor(9 * m.t * m.t / spec.divisor)
  -- The phase ends the first frame the parabola comes back down through zero,
  -- and the app SNAPS the offset to zero rather than letting it land wherever
  -- the integer arithmetic put it -- which is why the Pokemon finishes exactly
  -- on the ground each time instead of a pixel or two into it.
  if m.carry > 0 and y <= 0 then
    m.oy = 0
    m.carry = 0
    m.t = 0
    m.phase = m.phase + 1
    return ARC[m.phase] == nil
  end
  m.t = m.t + 1
  m.carry = y
  m.ox = m.ox + spec.dx
  if spec.half then
    y = math.floor(y / 2)
    if y > spec.cap then y = spec.cap end
  end
  m.oy = y
  return false
end

function Gen4RowanIntro:spawnMon()
  self.ball.stage = "spawn"
  self.ball.t = 0
  self.mon = {
    ox = RISE_DRIFT, oy = ARC[1].base,
    phase = 1, t = 0, carry = 0, glow = GLOW_FRAMES,
  }
end

function Gen4RowanIntro:tickBall()
  local b = self.ball
  if b.stage == "push" then
    if b.hold > 0 then
      b.hold = b.hold - 1
    else
      b.frame = b.frame + 1
      if b.frame > BALL_PICTURES then
        b.stage, b.t, b.flash = "flash", 0, 1
      else
        b.hold = BALL_FRAME_HOLD - 1
      end
    end
    return
  end

  if b.stage == "flash" then
    b.t = b.t + 1
    local spec = BALL_FLASHES[b.flash]
    if not spec or b.t >= spec.steps then
      b.flash = b.flash + 1
      b.t = 0
      if b.flash > #BALL_FLASHES then return self:spawnMon() end
    end
    return
  end

  if b.stage == "spawn" then
    b.t = b.t + 1
    if self.mon.glow > 0 then self.mon.glow = self.mon.glow - 1 end
    if self:tickArc() then b.stage, b.t = "settle", 0 end
    return
  end

  if b.stage == "settle" then
    b.t = b.t + 1
    if b.t >= SETTLE_FRAMES then
      -- The ball is finished; the Pokemon stays for the next line.
      self.ball = nil
      self:beginStep(self.step + 1)
    end
  end
end

-- The Pokemon is put away: a sixteen-frame layer fade and then a pause before
-- Rowan speaks again.
function Gen4RowanIntro:tickPutAway()
  local p = self.putaway
  p.t = p.t + 1
  if p.t == FADE_FRAMES then self.mon = nil end
  if p.t >= FADE_FRAMES + GAP_FRAMES then
    self.putaway = nil
    self:beginStep(self.step + 1)
  end
end

-- Buneary's own front sprite, out of the species table.  Nil on a cache that
-- has no sprite for it, which costs the picture and not the sequence.
function Gen4RowanIntro:monImage()
  if self.monImageCache ~= nil then return self.monImageCache or nil end
  local path = Sprites.path(self.game.data, MON_SPECIES, "front",
                            { kind = "intro" })
  self.monImageCache = path and self:img(path) or false
  return self.monImageCache or nil
end

-- -------------------------------------------------------- the two avatars --

function Gen4RowanIntro:newGenderState()
  return {
    stage = "fadeIn", t = 0, shift = SPREAD,
    boy = { frame = 1, hold = 0 },
    girl = { frame = 1, hold = 0 },
  }
end

function Gen4RowanIntro:tickRun()
  local side = self.gender[self.answers.gender]
  if not side then return end
  if side.hold > 0 then
    side.hold = side.hold - 1
  else
    side.frame = side.frame % #RUN.boy + 1
    side.hold = RUN_HOLD - 1
  end
end

function Gen4RowanIntro:updateGender()
  local G = self.gender
  local input = self.game.input
  if not (G and input) then return end

  if G.stage == "fadeIn" then
    G.t = G.t + 1
    -- One fade each, in the app's order: the boy, then the girl.
    if G.t >= FADE_FRAMES * 2 then G.stage, G.t = "choose", 0 end
    return
  end

  if G.stage == "choose" then
    self:tickRun()
    if input:wasPressed("left") or input:wasPressed("right") then
      self.answers.gender = (self.answers.gender == "boy") and "girl" or "boy"
    elseif input:wasPressed("a") then
      G.stage, G.t = "fadeOther", 0
    end
    return
  end

  if G.stage == "fadeOther" then
    G.t = G.t + 1
    if G.t >= FADE_FRAMES then G.stage, G.t = "centre", 0 end
    return
  end

  if G.stage == "centre" then
    G.shift = math.max(0, G.shift - CENTRE_STEP)
    if G.shift == 0 then
      G.stage, G.yesno, G.yes = "confirm", false, true
      self.pages = self:pagesOf((self.rec.text or {})[
        (self.answers.gender == "girl") and "confirmGirl" or "confirmBoy"])
      self.page = 1
    end
    return
  end

  if G.stage == "confirm" then
    if G.yesno then
      if input:wasPressed("up") or input:wasPressed("down")
         or input:wasPressed("left") or input:wasPressed("right") then
        G.yes = not G.yes
      elseif input:wasPressed("a") then
        if G.yes then return self:chooseGender(self.answers.gender) end
        G.stage, G.t = "again", 0
      elseif input:wasPressed("b") then
        G.stage, G.t = "again", 0
      end
      return
    end
    if input:wasPressed("a") or input:wasPressed("b")
       or input:wasPressed("start") then
      if self.page < #self.pages then
        self.page = self.page + 1
      else
        G.yesno = true
      end
    end
    return
  end

  if G.stage == "again" then
    -- NO: the chosen one fades out and the pair comes back, which is the app's
    -- RI_STATE_GENDR_REPEAT returning to the same prep state it started in.
    G.t = G.t + 1
    if G.t >= FADE_FRAMES then
      self.gender = self:newGenderState()
      self.pages = self:pagesOf((self.rec.text or {})[
        (self:currentStep() or {}).text])
      self.page = 1
    end
  end
end

function Gen4RowanIntro:finish()
  if self.done then return end
  self.done = true
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

function Gen4RowanIntro:update()
  self.blink = (self.blink + 1) % 60
  if self.finished then return self:finish() end
  local input = self.game.input
  if not input then return end

  -- The two animated scenes run on the frame clock and take no input while they
  -- are playing, which is what the app does: every one of these states is
  -- driven by a counter and reads no keys.
  if self.putaway then return self:tickPutAway() end
  if self.ball and self.ball.stage ~= "wait" then return self:tickBall() end
  if self.phase == "gender" then return self:updateGender() end

  if input:wasPressed("a") or input:wasPressed("b")
     or input:wasPressed("start") then
    if self.sayThenAdvance and self.page >= #self.pages then
      self.sayThenAdvance = nil
      return self:beginStep(self.step + 1)
    end
    self:advance()
  end
end

-- ------------------------------------------------------------------ draw --

-- Both avatars, and only the one you are pointing at is moving.
function Gen4RowanIntro:drawGender()
  local g = love.graphics
  local G = self.gender
  if not G then return end
  local chosen = self.answers.gender
  for _, side in ipairs({ "boy", "girl" }) do
    local alpha = 1
    if G.stage == "fadeIn" then
      -- The boy fades in first and the girl second, each over its own sixteen
      -- frames, which is two separate RowanIntro_FadeBgLayer calls.
      local start = (side == "boy") and 0 or FADE_FRAMES
      alpha = math.max(0, math.min(1, (G.t - start) / FADE_FRAMES))
    elseif side ~= chosen then
      if G.stage == "choose" then
        alpha = DIM
      elseif G.stage == "fadeOther" then
        alpha = DIM * (1 - G.t / FADE_FRAMES)
      else
        alpha = 0
      end
    elseif G.stage == "again" then
      alpha = 1 - G.t / FADE_FRAMES
    end
    if alpha > 0 then
      local frame = RUN[side][(G[side] or {}).frame or 1]
      local figure = self:figure(frame)
        or self:figure((self.rec.role or {})[side] or frame)
      if figure then
        g.setColor(1, 1, 1, alpha)
        g.draw(figure, (side == "boy") and G.shift or -G.shift, 0)
      end
    end
  end
  g.setColor(1, 1, 1, 1)
end

-- The Pokemon, tinted toward the release colour by however much of the blend is
-- left.  Two passes rather than one: multiplying the sprite by a colour can
-- only darken it, and the cartridge is REPLACING its palette with that colour,
-- so the second pass is additive and the first is scaled down to match -- which
-- gives pixel * (1 - w) + glow * w exactly, with the sprite's own alpha as the
-- mask both times.
function Gen4RowanIntro:drawMon(alpha)
  local m = self.mon
  if not m then return end
  local image = self:monImage()
  if not image then return end
  local g = love.graphics
  local x = MON_X - m.ox
  local y = MON_Y - m.oy
  local iw, ih = image:getDimensions()
  local sx = (iw > 0) and (MON_SIZE / iw) or 1
  local sy = (ih > 0) and (MON_SIZE / ih) or 1
  local w = math.floor(m.glow / GLOW_DIVISOR) / FLASH_MAX
  if w > 1 then w = 1 end
  g.setColor(1 - w, 1 - w, 1 - w, alpha)
  g.draw(image, x, y, 0, sx, sy)
  if w > 0 then
    local mode, alphaMode = g.getBlendMode()
    g.setBlendMode("add", "alphamultiply")
    g.setColor(GLOW[1] * w, GLOW[2] * w, GLOW[3] * w, alpha)
    g.draw(image, x, y, 0, sx, sy)
    g.setBlendMode(mode, alphaMode)
  end
  g.setColor(1, 1, 1, 1)
end

function Gen4RowanIntro:drawScene()
  local g = love.graphics
  if self.phase == "tv" then
    local tv = self.rec.tv or {}
    for _, key in ipairs({ "broadcast", "scanlines", "bezel" }) do
      local image = self:img(tv[key])
      if image then
        g.setColor(1, 1, 1, 1)
        local iw, ih = image:getDimensions()
        -- The three layers are 256x256 because that is the background size the
        -- hardware uses; the screen is the top 192 rows of it.
        local quad = g.newQuad(0, 0, math.min(W, iw), math.min(H, ih), iw, ih)
        g.draw(image, quad, 0, 0)
      end
    end
    return
  end

  local step = self:currentStep()
  local backdrop = self:backdrop((step and step.backdrop) or "speech")
    or self:backdrop("plain")
  if backdrop then
    g.setColor(1, 1, 1, 1)
    g.draw(backdrop, 0, 0)
  end

  if self.phase == "gender" then
    self:drawGender()
    return
  end

  if step and step.figure then
    local role = self.rec.role or {}
    local key = step.figure
    if key == "boy" or key == "girl" then key = role[key] or (key .. "_1") end
    local figure = self:figure(key)
    if figure then
      g.setColor(1, 1, 1, 1)
      g.draw(figure, 0, 0)
    end
  end

  -- THE BALL SITS ON TOP OF THE SCENE, not instead of it.
  --
  -- This used to draw the ball picture and RETURN, on the reading that it
  -- "owns the screen because on the cartridge it owns a screen".  That reading
  -- survived only because the picture was wrong: intro member 40's tilemap was
  -- composed without the tile base its sheet is loaded at, so what came out
  -- was a full-screen field of one repeated tile -- something that really did
  -- look like it owned the screen.  See Gen4IntroScene.BALL.tileFirst.
  --
  -- Composed correctly it is a 42x42 BUTTON on transparency, centred: three
  -- pictures of the ball's button being pushed in and lighting up, the third
  -- yellow.  Drawn alone that is a black screen with a button on it; drawn
  -- last, over Rowan and his backdrop, it is the step the cartridge plays with
  -- the two screens side by side.
  --
  -- No ball art at all -- a cache imported before the ball was extracted --
  -- still plays the release, because the Pokemon is the species' own sprite
  -- and does not come from this archive.
  local ball = self.ball
  if ball and (ball.stage == "wait" or ball.stage == "push"
               or ball.stage == "flash") then
    local picture = self:img((self.rec.ball or {})[ball.frame])
    if picture then
      g.setColor(1, 1, 1, 1)
      g.draw(picture, 0, 0)
    end
  end
end

function Gen4RowanIntro:draw()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  if not self.rec then return end

  self:drawScene()

  -- Platinum's own message box, which Font.drawDialogueBox draws from the
  -- eighteen-tile strip the graphics stage wrote.
  Font.drawDialogueBox(BOX.tx, BOX.ty, BOX.tw, BOX.th)

  -- Drawn at white: the Gen 4 font page is pre-tinted (dark letter, light
  -- shadow) and multiplying it by black paints the shadow black too.
  local page = self.pages and self.pages[self.page] or ""
  local y = TEXT_Y
  for line in (tostring(page) .. "\n"):gmatch("([^\n]*)\n") do
    -- The interior is two lines; the third would land on the bottom border.
    if y >= TEXT_Y + LINE_H * 2 then break end
    Font.draw(line, TEXT_X, y)
    y = y + LINE_H
  end

  -- The yes/no the app puts up after the confirm line.  `{YESNO 0}` is stripped
  -- out of the text upstream precisely because the box is drawn rather than
  -- printed.
  local G = self.gender
  if G and G.stage == "confirm" and G.yesno then
    local bx, by, bw, bh = 24, 6, 7, 6
    Font.drawBox(bx, by, bw, bh)
    local words = self.rec.text or {}
    Font.draw(words.yes or Strings("YES"), (bx + 2) * 8, (by + 1) * 8 + 3)
    Font.draw(words.no or Strings("NO"), (bx + 2) * 8, (by + 3) * 8 + 3)
    Font.drawCode(Theme.cursor, (bx + 1) * 8,
                  (by + (G.yes and 1 or 3)) * 8 + 3)
  end

  -- THE FLASH IS OVER EVERYTHING, text included: its plane mask is BG0|BG1|BG3
  -- and BG0 is the layer the message box lives on.  The Pokemon is on BG2 and
  -- is deliberately NOT in that mask, so it is drawn after this.
  local flash = self:flash()
  if flash and flash > 0 then
    g.setColor(1, 1, 1, math.min(1, flash))
    g.rectangle("fill", 0, 0, W, H)
  end
  -- ...so it is drawn HERE, once, after the flash rectangle, whatever stage the
  -- scene is in.  Drawing it in drawScene as well is the double-draw that made
  -- the glow pass land twice.
  if self.mon then
    local alpha = 1
    if self.putaway then
      alpha = math.max(0, 1 - self.putaway.t / FADE_FRAMES)
    end
    self:drawMon(alpha)
  end
  g.setColor(1, 1, 1, 1)
end

return Gen4RowanIntro
