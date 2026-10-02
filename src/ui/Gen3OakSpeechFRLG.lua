-- Professor Oak's introduction: FireRed's NEW GAME (pokefirered src/oak_speech.c).
--
-- Not BirchSpeech with a different professor.  FireRed's opens with a
-- three-page CONTROLS guide on a blue field, then three pages of the Pikachu
-- "world you are about to enter" card, and only then fades into Oak on his
-- platform: his welcome, NIDORAN♀ out of a Poké Ball, BOY or GIRL, the
-- player's name, his grandson and HIS name (NEW NAME or one of four), and the
-- player shrinking away into the world.
--
-- Everything drawn or said here is constants.gen3FRLGOakSpeech, which
-- RomExtractorGen3:extractFireRedOakSpeech reads off the cartridge.  The
-- sequence is written as a coroutine so it reads in the order oak_speech.c's
-- tasks chain; waits tick from update when this is the top state and from
-- animate while a text box sits over it.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Music = require("src.core.Music")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")

local Speech = {}
Speech.__index = Speech
Speech.isOpaque = true
Speech.holdsUIAnchors = true

local GBA_W, GBA_H = 240, 160

-- MUS_NEW_GAME_INSTRUCT / _INTRO / _EXIT and MUS_ROUTE24 (Oak's theme here)
local SONG_GUIDE, SONG_PIKACHU, SONG_PIKACHU_EXIT, SONG_OAK =
  "SONG_143", "SONG_144", "SONG_145", "SONG_124"

-- sControlsGuide_WindowTemplates: pixel y of each text window, x = 6*8+6
local GUIDE_TEXT = {
  { { key = "guideIntro", x = 2, y = 56 } },
  { { key = "guideDPad", x = 54, y = 24 }, { key = "guideA", x = 54, y = 80 },
    { key = "guideB", x = 54, y = 120 } },
  { { key = "guideStart", x = 54, y = 24 }, { key = "guideSelect", x = 54, y = 64 },
    { key = "guideLR", x = 54, y = 104 } },
}

local PIC_X, PIC_Y = 88, 16          -- LoadTrainerPic: BG2 tile (11,2)
local PLATFORM_X, PLATFORM_Y = 72, 96 -- three 32x32 sprites centred at (88+32i,112)
local NIDORAN_X, NIDORAN_Y = 64, 64  -- a 64x64 mon sprite centred at (96,96)
local BALL_X, BALL_Y = 100, 66       -- where the ball opens
local WHITE = { 1, 1, 1 }
local DARK = { 0.29, 0.29, 0.29 }
local LIGHT = { 0.84, 0.84, 0.81 }

function Speech:wantsFillScale() return true end
function Speech:uiSize() return GBA_W, GBA_H end
function Speech:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1, math.ceil(GBA_H / 8) - 1) }
end

function Speech.new(game, onDone)
  local self = setmetatable({}, Speech)
  self.game = game
  self.onDone = onDone
  self.rec = (game.data.constants or {}).gen3FRLGOakSpeech or {}
  self.text = self.rec.text or {}
  self.images = {}
  self.phase = "guide"
  self.page = 1
  self.textAlpha = 1
  self.black = 1          -- whole-screen fade to black
  self.picAlpha = 0       -- trainer pic + platform
  self.picTarget = 0
  -- Visual offset of BG2 trainer art + the platform OBJ sprites.  Oak speech's
  -- task variable counts DOWN to -60, but BG2 HOFS=-60 displays the bitmap
  -- sixty pixels to the RIGHT, while gSpriteCoordOffsetX is explicitly +60.
  -- Store the screen-space result here so draw() does not invert it again.
  self.picOffset = 0
  self.picScale = 1
  self.picWhite = 0
  self.nidoAlpha, self.nidoScale, self.nidoWhite = 0, 0, 0
  self.ballAlpha, self.ballFrame = 0, 1
  self.pikaTimer = 0
  self.pic = nil
  return self
end

-- ---------------------------------------------------------------- assets --

function Speech:image(key, directPath)
  local rec = directPath or (self.rec.images or {})[key]
  local path = type(rec) == "table" and rec.path or rec
  if type(path) ~= "string" then return nil end
  local img = self.images[path]
  if img == nil then
    local ok, loaded = pcall(Assets.image, path)
    img = ok and loaded or false
    if img then img:setFilter("nearest", "nearest") end
    self.images[path] = img
  end
  return img or nil, type(rec) == "table" and rec or nil
end

function Speech:nidoranPic()
  if self.nidoran == nil then
    local ok, path = pcall(function()
      return require("src.pokemon.Sprites").path(self.game.data, "NIDORAN", "front")
    end)
    local okImg, img = false, nil
    if ok and path then okImg, img = pcall(love.graphics.newImage, path) end
    self.nidoran = okImg and img or false
  end
  return self.nidoran or nil
end

local function playSong(data, song)
  if data.audio and data.audio.songs and data.audio.songs[song] then
    pcall(Music.play, data, song)
  end
end

-- the ROM's strings end most pages with a page break; a trailing one would
-- be an empty page to click through
local function clean(s)
  if type(s) ~= "string" then return nil end
  return (s:gsub("[\f\n]+$", ""))
end

-- -------------------------------------------------------------- sequence --

function Speech:enter()
  if not self.text.welcome then
    Logger.warn("gen3 frlg oak speech: this cache carries no Oak speech -- re-import")
  end
  playSong(self.game.data, SONG_GUIDE)
  self.co = coroutine.create(function() self:run() end)
  self:resume()
end

function Speech:resume()
  if not self.co or coroutine.status(self.co) ~= "suspended" then return end
  local ok, err = coroutine.resume(self.co)
  if not ok then
    Logger.warn("gen3 frlg oak speech: %s", tostring(err))
    self.co = nil
    self:finish()
  end
end

function Speech:wait(frames)
  self.waitFrames = frames
  coroutine.yield()
end

-- ramp a field toward a value by `step` per frame without waiting
function Speech:ramp(field, target, step)
  self.tweens = self.tweens or {}
  self.tweens[field] = { target = target, step = step }
end

-- ramp a field toward a value by `step` per frame, waiting until it lands
function Speech:tween(field, target, step)
  if self[field] == target then return end
  self:ramp(field, target, step)
  self.waitTween = field
  coroutine.yield()
end

function Speech:ballRecord()
  return (self.game.data.constants or {}).gen3BallAnim or {}
end

function Speech:waitInput()
  self.pending = nil
  self.wantInput = true
  coroutine.yield()
  local key = self.pending
  self.pending = nil
  return key
end

function Speech:say(key)
  local line = clean(self.text[key])
  if not line then return end
  self.game.stack:push(TextBox.new(self.game, line, function() self:resume() end))
  coroutine.yield()
end

-- a question: the box stays up under the menu that answers it
function Speech:ask(key)
  local line = clean(self.text[key]) or ""
  local box
  box = TextBox.new(self.game, line, nil, { stay = { onShown = function()
    self:resume()
  end } })
  self.game.stack:push(box)
  coroutine.yield()
  return box
end

function Speech:closeBox(box)
  local stack = self.game.stack
  if box and stack:top() == box then stack:pop() end
end

function Speech:menu(labels, opts)
  local Menu = require("src.ui.Menu")
  local choice
  opts = opts or {}
  local items = {}
  for i, label in ipairs(labels) do
    items[i] = { label = label, onSelect = function()
      choice = i
      -- Menu pops itself after onSelect; resume on the next tick
      self.waitFrames = 1
    end }
  end
  -- oak_speech.c passes WindowTemplate CONTENT coordinates to these menus.
  -- Their frame is one tile outside the template on every side and every row
  -- starts at y=1 with a 16-pixel pitch.  A fresh FireRed save has Frame Type
  -- 1 (optionsWindowFrameType=0), so keep the professor intro on that frame
  -- even though this port deliberately persists desktop options across New
  -- Game.
  opts.gbaWindow = true
  opts.th = opts.th or (#labels * 2)
  opts.frameIndex = 1
  opts.cancelable = opts.onCancelIndex ~= nil
  if opts.onCancelIndex then
    opts.onCancel = function() choice = opts.onCancelIndex; self.waitFrames = 1 end
  end
  local menu = Menu.new(self.game, items, opts)
  -- laid out on the GBA's 240x160 tile grid, not centred as a Game Boy menu
  function menu.uiSize() return GBA_W, GBA_H end
  self.game.stack:push(menu)
  self.waitFrames = -1
  coroutine.yield()
  return choice
end

function Speech:naming(title, default, apply, opts)
  local done
  local push = { title = title, default = default,
                 maxLen = (self.game.data.constants or {}).playerNameLength or 7 }
  for k, v in pairs(opts or {}) do push[k] = v end
  push.onDone = function(name)
    if name == nil or name == "" then name = default end
    apply(name)
    done = true
    self.waitFrames = 1
  end
  require("src.ui.Screens").push(self.game, "NamingScreen", push)
  self.waitFrames = -1
  coroutine.yield()
  return done
end

function Speech:run()
  local data = self.game.data
  local save = self.game.save
  local player = save and save.player or {}

  -- ---- CONTROLS guide ----
  self:tween("black", 0, 1 / 16)
  local page = 1
  while true do
    self.page = page
    local key = self:waitInput()
    if key == "a" or (key == "b" and page > 1) then
      self:tween("textAlpha", 0, 1 / 8)
      page = page + (key == "a" and 1 or -1)
      if page > 3 then break end
      self.page = page
      self:tween("textAlpha", 1, 1 / 8)
    end
  end
  self:tween("black", 1, 1 / 8)

  -- ---- the Pikachu pages ----
  self:wait(32)
  playSong(data, SONG_PIKACHU)
  self.phase = "pikachu"
  self.page, self.textAlpha = 1, 1
  self:tween("black", 0, 1 / 8)
  page = 1
  while true do
    local key = self:waitInput()
    if key == "a" or (key == "b" and page > 1) then
      page = page + (key == "a" and 1 or -1)
      if page > 3 then break end
      self:tween("textAlpha", 0, 1 / 8)
      self.page = page
      self:tween("textAlpha", 1, 1 / 8)
    end
  end
  playSong(data, SONG_PIKACHU_EXIT)
  self:wait(24)
  self:tween("black", 1, 1 / 8)

  -- ---- Oak ----
  self:wait(80)
  self.phase = "oak"
  self.pic = "oak"
  self.picAlpha, self.picTarget = 1, 1
  playSong(data, SONG_OAK)
  self:tween("black", 0, 1 / 48)
  self:wait(80)
  self:say("welcome")
  self:say("thisWorld")
  self:wait(30)
  -- NIDORAN♀ out of the ball (CreatePokeballSpriteToReleaseMon at 100,66)
  local Sound = require("src.core.Sound")
  local sounds = self:ballRecord().sounds or {}
  self.ballFrame, self.ballAlpha = 1, 1
  self:wait(12)
  self.ballFrame, self.ringT = 3, 0
  if sounds.open then pcall(Sound.playId, data, sounds.open) end
  self:ramp("ringT", 1, 1 / 24)
  self.nidoAlpha, self.nidoWhite = 1, 1
  self:tween("nidoScale", 1, 1 / 16)
  self:ramp("ballAlpha", 0, 1 / 8)
  self:tween("nidoWhite", 0, 1 / 10)
  if self.tweens then self.tweens.ringT = nil end
  self.ringT = nil
  pcall(Sound.playCry, data, "NIDORAN")
  self:say("inhabited")
  self:say("iStudy")
  -- ...and back in (CreateTradePokeballSprite)
  self.ballFrame, self.ballAlpha = 3, 1
  self:tween("nidoWhite", 1, 1 / 8)
  self:tween("nidoScale", 0, 1 / 16)
  self.nidoAlpha = 0
  self.ballFrame = 1
  if sounds.absorb then pcall(Sound.playId, data, sounds.absorb) end
  self:wait(24)
  self:tween("ballAlpha", 0, 1 / 8)
  self:wait(24)
  self:say("tellMe")
  self:tween("picAlpha", 0, 1 / 48)
  self:wait(48)

  -- BOY or GIRL
  local box = self:ask("askGender")
  local g = self:menu({ clean(self.text.boy) or Strings("BOY"),
                        clean(self.text.girl) or Strings("GIRL") },
                      { tx = 18, ty = 9, tw = 9 })
  self:closeBox(box)
  local gender = (g == 2) and "girl" or "boy"
  player.gender = gender
  local overworld = self.game.overworld
  local avatar = overworld and overworld.player
  if avatar and avatar.refreshForm then
    pcall(function() avatar:refreshForm(data) end)
  end
  self.pic = (gender == "girl") and "leaf" or "red"
  self:tween("picAlpha", 1, 1 / 48)
  self:wait(32)

  -- the player's name
  local names = (gender == "girl") and self.rec.femaleNames or self.rec.maleNames
  local defaultName = (names and names[1]) or "RED"
  while true do
    self:say("yourName")
    self:tween("black", 1, 1 / 16)
    self:naming(Strings("YOUR NAME?"), defaultName, function(name) player.name = name end,
                { kind = "player" })
    self.picOffset = 0
    self:tween("black", 0, 1 / 16)
    box = self:ask("soYourName")
    self:wait(25)
    local yes = self:menu({ Strings("YES"), Strings("NO") },
                          { tx = 2, ty = 2, tw = 6, onCancelIndex = 2 })
    self:closeBox(box)
    if yes == 1 then break end
  end

  -- the rival
  self:tween("picAlpha", 0, 1 / 48)
  self:wait(40)
  self.pic = "rival"
  self:tween("picAlpha", 1, 1 / 48)
  local rivals = self.rec.rivalNames or {}
  local question = "whatWasHisName"
  while true do
    box = self:ask(question)
    question = "rivalNameAgain"
    if self.picOffset < 60 then self:tween("picOffset", 60, 2) end
    local labels = { clean(self.text.newName) or Strings("NEW NAME") }
    for i = 1, 4 do labels[#labels + 1] = rivals[i] end
    local pick = self:menu(labels, { tx = 2, ty = 2, tw = 12 })
    self:closeBox(box)
    if pick == 1 then
      self:tween("black", 1, 1 / 16)
      self:naming(Strings("RIVAL's NAME?"), rivals[1] or "GREEN",
                  function(name) player.rival = name end,
                  { kind = "rival" })
      self:tween("black", 0, 1 / 16)
    else
      player.rival = rivals[pick - 1] or "GREEN"
    end
    box = self:ask("confirmRival")
    self:wait(25)
    local yes = self:menu({ Strings("YES"), Strings("NO") },
                          { tx = 2, ty = 2, tw = 6, onCancelIndex = 2 })
    self:closeBox(box)
    if yes == 1 then break end
  end
  self:say("rememberRival")

  -- back to the player, and away
  self:tween("picAlpha", 0, 1 / 48)
  self.pic = (gender == "girl") and "leaf" or "red"
  self.picOffset = 0
  self:tween("picAlpha", 1, 1 / 48)
  self:say("letsGo")
  self:wait(30)
  pcall(Music.fadeOut)
  self.exiting = true
  for step = 1, 5 do
    self:wait(20)
    self.picScale = (256 - 32 * step) / 256
    if step == 2 then pcall(require("src.core.Sound").play, data, "SE_WARP_IN") end
  end
  self:wait(36)
  self:tween("black", 1, 1 / 16)
  self:finish()
end

function Speech:finish()
  if self.finished then return end
  self.finished = true
  local ow = self.game.overworld
  local mapId = (ow and ow.map and ow.map.id)
                or (self.game.save.player and self.game.save.player.map)
  if mapId then pcall(Music.playMap, self.game.data, mapId) end
  if self.game.stack:top() == self then self.game.stack:pop() end
  if self.onDone then self.onDone() end
end

-- ------------------------------------------------------------------ tick --

function Speech:tick()
  self.pikaTimer = self.pikaTimer + 1
  if self.exiting and self.picWhite < 1 then
    self.picWhite = math.min(1, self.picWhite + 1 / 60)
  end
  for field, t in pairs(self.tweens or {}) do
    local v = self[field]
    if v < t.target then v = math.min(t.target, v + t.step)
    else v = math.max(t.target, v - t.step) end
    self[field] = v
    if v == t.target then
      self.tweens[field] = nil
      if self.waitTween == field then
        self.waitTween = nil
        self:resume()
        return
      end
    end
  end
  if self.waitFrames and self.waitFrames > 0 then
    self.waitFrames = self.waitFrames - 1
    if self.waitFrames == 0 then
      self.waitFrames = nil
      self:resume()
    end
  end
end

function Speech:animate()
  self:tick()
end

function Speech:update()
  if self.wantInput then
    local input = self.game.input
    local key = input and ((input:wasPressed("a") and "a")
                           or (input:wasPressed("b") and "b"))
    if key then
      self.wantInput = false
      self.pending = key
      self:resume()
      return
    end
  end
  self:tick()
end

function Speech:keypressed(key)
  if self.wantInput and (key == "a" or key == "b") then
    self.wantInput = false
    self.pending = key
    self:resume()
  end
end

-- ------------------------------------------------------------------ draw --

local function drawLines(text, x, y, pitch, ink, shadow, alpha)
  if type(text) ~= "string" then return end
  local two = Font.beginTwoTone({ ink[1], ink[2], ink[3], alpha },
                                { shadow[1], shadow[2], shadow[3], alpha })
  if not two then love.graphics.setColor(ink[1], ink[2], ink[3], alpha) end
  local row = 0
  for line in (text:gsub("\f", "\n") .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" then Font.draw(line, x, y + row * pitch) end
    row = row + 1
  end
  if two then Font.endTwoTone() end
  love.graphics.setColor(1, 1, 1, 1)
end

function Speech:drawTopBar(right)
  love.graphics.setColor(LIGHT[1], LIGHT[2], LIGHT[3], 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, 16)
  love.graphics.setColor(1, 1, 1, 1)
  if self.phase == "guide" and self.page == 1 then
    drawLines(clean(self.text.controls) or "CONTROLS", 4, 1, 14, DARK, WHITE, 1)
  end
  -- {A_BUTTON} NEXT / {B_BUTTON} BACK: the button glyphs are control codes the
  -- text reader drops, so they are drawn here as the small keypad icons
  local function icon(letter, x)
    love.graphics.setColor(DARK[1], DARK[2], DARK[3], 1)
    love.graphics.rectangle("fill", x, 3, 11, 10, 3, 3)
    love.graphics.setColor(1, 1, 1, 1)
    drawLines(letter, x + 3, 1, 14, WHITE, DARK, 1)
    return x + 13
  end
  local nextWord = ((clean(self.text.aNext) or "NEXT"):gsub("^%s+", ""))
  local parts = { { "A", nextWord } }
  if self.page > 1 then parts[2] = { "B", "BACK" } end
  local width = 0
  for _, p in ipairs(parts) do width = width + 13 + Font.width(p[2]) + 6 end
  local x = GBA_W - width - 2
  for _, p in ipairs(parts) do
    x = icon(p[1], x)
    drawLines(p[2], x, 1, 14, DARK, WHITE, 1)
    x = x + Font.width(p[2]) + 6
  end
end

function Speech:drawGuide()
  local bg = self.rec.backdrop or { 16, 115, 230 }
  love.graphics.setColor(bg[1] / 255, bg[2] / 255, bg[3] / 255, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  love.graphics.setColor(1, 1, 1, 1)
  local icons = self.page == 2 and self:image("guidePage2")
                or self.page == 3 and self:image("guidePage3") or nil
  if icons then
    love.graphics.setColor(1, 1, 1, self.textAlpha)
    love.graphics.draw(icons, 0, 0)
  end
  for _, t in ipairs(GUIDE_TEXT[self.page] or {}) do
    drawLines(clean(self.text[t.key]), t.x, t.y, 16, WHITE, DARK, self.textAlpha)
  end
  self:drawTopBar()
end

function Speech:drawPikachu()
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  love.graphics.setColor(1, 1, 1, 1)
  local bg = self:image("pikachuBg")
  if bg then love.graphics.draw(bg, 0, 0) end
  drawLines((self.rec.pikachuPages or {})[self.page], 11, 37, 14, DARK, LIGHT,
            self.textAlpha)
  self:drawTopBar()
  -- the body animates between two frames; the ears and eyes ride its frame
  local frame = math.floor(self.pikaTimer / 30) % 2
  local function sheet(key, x, y)
    local img, rec = self:image(key)
    if not img then return end
    local fw = (rec and rec.cols or 4) * 8
    local fh = (rec and rec.rows or 4) * 8
    local frames = rec and rec.frames or 1
    local quad = love.graphics.newQuad(math.min(frame, frames - 1) * fw, 0, fw, fh,
                                       img:getDimensions())
    love.graphics.draw(img, quad, x, y)
  end
  sheet("pikachuBody", 0, 1)
  sheet("pikachuEars", 0, 1 + frame)
  sheet("pikachuEyes", 16, 9 + frame)
end

function Speech:drawOak()
  local bg = self:image("oakBg")
  love.graphics.setColor(1, 1, 1, 1)
  if bg then love.graphics.draw(bg, 0, 0)
  else
    love.graphics.setColor(0.9, 0.95, 0.93, 1)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  end
  local alpha = self.picAlpha
  if not self.exiting then
    local plat = self:image("platform")
    if plat then
      love.graphics.setColor(1, 1, 1, self.picAlpha)
      love.graphics.draw(plat, PLATFORM_X + self.picOffset, PLATFORM_Y)
    end
  end
  local pic = self.pic and self:image(self.pic)
  if pic then
    local s = self.picScale
    local cx, cy = 120, 84
    local x = cx + (PIC_X + self.picOffset - cx) * s
    local y = cy + (PIC_Y - cy) * s
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(pic, x, y, 0, s, s)
    if self.picWhite > 0 then
      -- fade the silhouette toward white (BlendPalette to RGB_WHITE)
      love.graphics.setBlendMode("add")
      love.graphics.setColor(self.picWhite, self.picWhite, self.picWhite, 1)
      love.graphics.draw(pic, x, y, 0, s, s)
      love.graphics.setBlendMode("alpha")
    end
  end
  self:drawBall()
  local nido = self.nidoAlpha > 0 and self.nidoScale > 0 and self:nidoranPic()
  if nido then
    local w, h = nido:getDimensions()
    local s = self.nidoScale
    -- grows out of the ball and settles on its own spot
    local x = BALL_X + (NIDORAN_X + 32 - BALL_X) * s
    local y = BALL_Y + (NIDORAN_Y + 32 - BALL_Y) * s
    love.graphics.setColor(1, 1, 1, self.nidoAlpha)
    love.graphics.draw(nido, x, y, 0, s, s, w / 2, h / 2)
    local white = self.nidoWhite or 0
    if white > 0 then
      love.graphics.setBlendMode("add")
      love.graphics.setColor(white, white, white, 1)
      love.graphics.draw(nido, x, y, 0, s, s, w / 2, h / 2)
      love.graphics.setBlendMode("alpha")
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- the battle's own Poke Ball sheet (16x16, three frames a row, POKE BALL on
-- row 0) and its eight-point release ring
function Speech:drawBall()
  local rec = self:ballRecord()
  local images = rec.images or {}
  if (self.ballAlpha or 0) > 0 then
    local sheet = images.balls and self:image(nil, images.balls)
    if sheet then
      local size = rec.size or 16
      local iw, ih = sheet:getDimensions()
      local f = math.max(0, math.min((rec.frames or 3), self.ballFrame or 1) - 1)
      love.graphics.setColor(1, 1, 1, self.ballAlpha)
      love.graphics.draw(sheet, love.graphics.newQuad(f * size, 0, size, size, iw, ih),
                         BALL_X - size / 2, BALL_Y - size / 2)
    end
  end
  if self.ringT then
    local sheet = images.particles and self:image(nil, images.particles)
    local t = self.ringT
    local which = ((rec.balls or {})[1] or {}).particle or 0
    for i = 0, 7 do
      local a = i * math.pi / 4
      local px, py = BALL_X + math.sin(a) * 24 * t, BALL_Y + math.cos(a) * 24 * t
      love.graphics.setColor(1, 1, 1, 1 - t)
      if sheet then
        local iw, ih = sheet:getDimensions()
        local n = rec.particleFrames or 8
        love.graphics.draw(sheet, love.graphics.newQuad((which % n) * 8, 0, 8, 8, iw, ih),
                           px - 4, py - 4)
      else
        love.graphics.rectangle("fill", px - 2, py - 2, 4, 4)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Speech:draw()
  if self.phase == "guide" then self:drawGuide()
  elseif self.phase == "pikachu" then self:drawPikachu()
  else self:drawOak() end
  if self.black > 0 then
    love.graphics.setColor(0, 0, 0, self.black)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return Speech
