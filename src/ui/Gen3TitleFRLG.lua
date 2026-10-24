-- FireRed's title screen (pokefirered src/title_screen.c).
--
-- Four backgrounds out of the cartridge -- the dark border field, the
-- copyright / PRESS START strip, Charizard and the POKeMON FireRed logo --
-- and the embers Task_FlameSpawner throws up from the bottom of the screen.
-- constants.gen3FRLGTitle carries all of it (RomExtractorGen3:extractFireRedTitle).
--
-- The opening follows SetTitleScreenScene_FadeIn in shape: Charizard fades
-- in out of black, the border wipes in from the left while the copyright
-- strip slides in from the right (Task_TitleScreen_SlideWin0), Charizard
-- flashes white twice, and the logo comes up out of white.  A, B or START
-- during that skips straight to the running screen, as on the cartridge.

local Assets = require("src.render.Assets")
local Music = require("src.core.Music")
local Screens = require("src.ui.Screens")

local Title = {}
Title.__index = Title
Title.isOpaque = true

local W, H = 240, 160
local SONG_TITLE = "SONG_116" -- MUS_TITLE

function Title:wantsFillScale() return true end
function Title:uiSize() return W, H end
function Title:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function Title.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Title)
  self.game = game
  self.onNewGame, self.onContinue = opts.onNewGame, opts.onContinue
  self.rec = (game.data.constants or {}).gen3FRLGTitle or {}
  self.cache = {}
  self.frame = 0
  self.phase = "intro"
  self.flames = {}
  self.streaks = {}
  for i = 1, math.min(4, #(self.rec.streakY or {})) do
    self.streaks[i] = { x = W + 16 + 40 * (i - 1), y = self.rec.streakY[i], index = i }
  end
  self.spawnTimer, self.spawnDelay, self.offsetX = 0, 0, 0
  self.rng = love.math.newRandomGenerator(30840)
  self.blinkTimer, self.blinkOn = 0, false
  return self
end

function Title:img(key)
  local rec = (self.rec.images or {})[key]
  local path = type(rec) == "table" and rec.path or rec
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(Assets.image, path)
    self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil, rec
end

function Title:enter()
  local data = self.game.data
  if data.audio and data.audio.songs and data.audio.songs[SONG_TITLE] then
    pcall(Music.play, data, SONG_TITLE)
  end
end

-- ------------------------------------------------------------------ flow --

-- the intro's beats, in frames from the start
local T_MON_FADE = 10       -- Charizard out of black (16-step fade, delay 9)
local T_SLIDE = 60          -- border wipe + copyright slide
local T_FLASH1 = 70
local T_FLASH2 = 110
local T_LOGO = 150
local T_RUN = 190

local function clamp01(v) return math.max(0, math.min(1, v)) end

function Title:skipToRun()
  self.phase = "run"
  self.frame = T_RUN
end

function Title:animate()
  self.frame = self.frame + 1
  if self.phase == "intro" and self.frame >= T_RUN then self.phase = "run" end
  if self.phase == "run" or self.phase == "leaving" then
    self:tickBlink()
    self:tickFlames()
  end
  if self.phase == "leaving" then
    self.leaveTimer = self.leaveTimer + 1
    if self.leaveTimer == 90 then self.whiteOut = 0 end
    if self.whiteOut then
      self.whiteOut = math.min(1, self.whiteOut + 1 / 16)
      if self.whiteOut >= 1 and not self.opened then
        self.opened = true
        Screens.push(self.game, "Gen3MainMenu", {
          onNewGame = self.onNewGame, onContinue = self.onContinue,
        })
      end
    end
  end
end

function Title:update(dt)
  -- updated again means the main menu was backed out of
  if self.opened then self:resume() end
  self:animate(dt)
  local input = self.game.input
  if not input then return end
  local pressed = input:wasPressed("start") or input:wasPressed("a")
  if self.phase == "intro" and (pressed or input:wasPressed("b")) then
    self:skipToRun()
  elseif self.phase == "run" and pressed then
    self.phase, self.leaveTimer = "leaving", 0
    pcall(require("src.core.Sound").playCry, self.game.data, self.rec.cry or "CHARIZARD")
  end
end

-- the main menu came back down to us (B out of it): run again
function Title:resume()
  self.phase, self.opened, self.whiteOut = "run", nil, nil
end

-- Task_TitleScreen_BlinkPressStart: 60 frames lit, 30 blanked
function Title:tickBlink()
  self.blinkTimer = self.blinkTimer + 1
  if self.blinkTimer >= (self.blinkOn and 30 or 60) then
    self.blinkTimer = 0
    self.blinkOn = not self.blinkOn
  end
end

-- Task_FlameSpawner / SpriteCallback_TitleScreenFlame, positions in 1/16 px
local FLAME_DURATIONS = { 3, 6, 6, 6, 6, 6, 6, 6, 6, 6 }

function Title:spawnFlame(x, y, sx, sy, visible)
  self.flames[#self.flames + 1] = { px = x * 16, py = y * 16, sx = sx, sy = sy,
                                    anim = 1, t = 0, visible = visible }
end

function Title:tickFlames()
  if self.rec.effect == "leaves" then return self:tickLeaves() end
  local r = self.rng
  self.spawnTimer = self.spawnTimer + 1
  if self.spawnTimer >= self.spawnDelay then
    self.spawnTimer, self.spawnDelay = 0, 18
    local sx = r:random(0, 3) - 2
    local sy = r:random(0, 7) - 16
    local y = r:random(0, 2) + 116
    self:spawnFlame(r:random(0, W - 1), y, sx, sy, r:random(0, 15) >= 8)
    for _, fx in ipairs(self.rec.flameX or {}) do
      self:spawnFlame(self.offsetX + fx, y, sx, sy, true)
      sx = r:random(0, 3) - 2
      sy = r:random(0, 7) - 16
    end
    self.offsetX = (self.offsetX + 1) % 4
  end
  for i = #self.flames, 1, -1 do
    local f = self.flames[i]
    f.px = f.px - f.sx
    f.py = f.py + f.sy
    f.t = f.t + 1
    if f.t >= FLAME_DURATIONS[f.anim] then f.t, f.anim = 0, f.anim + 1 end
    local x, y = math.floor(f.px / 16), math.floor(f.py / 16)
    if x < -8 or y < 16 or y > 200 or f.anim > #FLAME_DURATIONS then
      table.remove(self.flames, i)
    end
  end
end

-- LeafGreen's Task_LeafSpawner / SpriteCallback_TitleScreenLeaf: the
-- eleven 16x16 frames loop, with leftward drift instead of rising embers.
function Title:tickLeaves()
  local r = self.rng
  self.spawnTimer = self.spawnTimer + 1
  if self.spawnTimer >= self.spawnDelay then
    self.spawnTimer, self.spawnDelay = 0, r:random(0, 5) + 6
    local roll = r:random(0, 29)
    local sx = roll < 6 and 16 or (roll < 12 and 24 or 48)
    local sy, y = r:random(0, 3) - 2, r:random(0, 87) + 32
    self:spawnFlame(W, y, sx, sy, true)
  end
  for i = #self.flames, 1, -1 do
    local f = self.flames[i]
    f.px, f.py = f.px - f.sx, f.py + f.sy
    f.t = f.t + 1
    if f.t >= 8 then f.t, f.anim = 0, f.anim % 11 + 1 end
    local x, y = math.floor(f.px / 16), math.floor(f.py / 16)
    if x < -8 or y < 16 or y > 200 then table.remove(self.flames, i) end
  end
  local ys = self.rec.streakY
  for _, s in ipairs(self.streaks) do
    s.x = s.x - 7
    if s.x < -16 then
      s.index = s.index % #ys + 1
      s.x, s.y = W + 16, ys[s.index]
    end
  end
end

-- ------------------------------------------------------------------ draw --

local function drawWhite(img, x, y, amount)
  if amount <= 0 then return end
  love.graphics.setBlendMode("add")
  love.graphics.setColor(amount, amount, amount, 1)
  love.graphics.draw(img, x, y)
  love.graphics.setBlendMode("alpha")
end

function Title:draw()
  local g = love.graphics
  local bd = self.rec.backdrop or { 0, 0, 0 }
  local intro = self.phase == "intro"
  local f = self.frame
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)

  -- border and copyright: wiped in from the left / slid in from the right
  local wipe = intro and clamp01((f - T_SLIDE) * 24 / W) or 1
  local border = self:img("border")
  if border and wipe > 0 then
    g.setScissor()
    local sx, sy, sw, sh = g.transformPoint(0, 0)
    local ex, ey = g.transformPoint(W * wipe, H)
    g.setScissor(math.floor(sx), math.floor(sy), math.max(0, math.ceil(ex - sx)),
                 math.max(0, math.ceil(ey - sy)))
    g.setColor(1, 1, 1, 1)
    g.draw(border, 0, 0)
    g.setScissor()
  end

  -- embers ride just over the border field
  local streak = self:img("streak")
  if streak and not intro then
    g.setColor(1, 1, 1, 1)
    for _, s in ipairs(self.streaks) do g.draw(streak, s.x - 16, s.y - 8) end
  end
  local flames, frec = self:img("flames")
  if flames and not intro then
    local size = (type(frec) == "table" and frec.size) or 16
    local iw, ih = flames:getDimensions()
    g.setColor(1, 1, 1, 1)
    for _, fl in ipairs(self.flames) do
      if fl.visible then
        local q = g.newQuad((fl.anim - 1) * size, 0, size, size, iw, ih)
        g.draw(flames, q, math.floor(fl.px / 16) - size / 2, math.floor(fl.py / 16) - size / 2)
      end
    end
  end

  local slide = intro and math.max(0, W - math.max(0, f - T_SLIDE) * 24) or 0
  local copyright = self:img((self.blinkOn and not intro) and "copyrightBlink" or "copyright")
  if copyright and (not intro or f >= T_SLIDE) then
    g.setColor(1, 1, 1, 1)
    g.draw(copyright, slide, 0)
  end

  -- Charizard: out of black, then two white flashes
  local mon = self:img("mon")
  if mon then
    local lit = intro and clamp01((f - T_MON_FADE) / 16) or 1
    g.setColor(lit, lit, lit, 1)
    g.draw(mon, 0, 0)
    if intro then
      local function flash(start)
        local d = f - start
        if d < 0 or d > 32 then return 0 end
        return d <= 16 and d / 16 or (32 - d) / 16
      end
      drawWhite(mon, 0, 0, math.max(flash(T_FLASH1), flash(T_FLASH2)))
    end
  end

  -- the logo comes up out of white
  local logo = self:img("logo")
  if logo and (not intro or f >= T_LOGO) then
    g.setColor(1, 1, 1, 1)
    g.draw(logo, 0, 0)
    if intro then drawWhite(logo, 0, 0, 1 - clamp01((f - T_LOGO) / 32)) end
  end

  if self.whiteOut then
    g.setColor(1, 1, 1, self.whiteOut)
    g.rectangle("fill", 0, 0, W, H)
  end
  g.setColor(1, 1, 1, 1)
end

return Title
