-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The wall clock in your bedroom, and the scene that makes you set it.
--
-- WHERE THIS COMES FROM.
--
-- Emerald's new game does not ask for the time on a menu; it makes you walk
-- upstairs and look at the clock on your bedroom wall. The clock is a BG
-- event on the map -- one of four in that room -- and its script is three
-- instructions:
--
--     fadescreen 1
--     special 157
--     waitstate
--
-- and then, on the far side of it, the story var advances and the flags that
-- let mum come upstairs are set. So special 157 IS this screen: the script
-- fades out, hands over, and waits for a state change. That identification is
-- read off the cartridge -- it is the bedroom clock's own script, it does
-- nothing but fade and call one special, and everything after it depends on
-- the clock having been set -- rather than taken from a list of names.
--
-- WHAT IT DOES WITH THE ANSWER.
--
-- The cartridge has a battery-backed real-time clock and this port does not,
-- so the time is stored as an OFFSET: what the player chose, and the moment
-- they chose it. Reading the clock later is that offset plus however long has
-- passed, which is the same thing the cartridge's RTC does and keeps a save
-- that sat closed for a week from waking up a week behind.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Strings = require("src.core.Strings")

local Gen3WallClock = {}
Gen3WallClock.__index = Gen3WallClock
Gen3WallClock.isOpaque = true

local GBA_W, GBA_H = 240, 160

-- RECONSTRUCTED geometry: the face is centred, the prompt sits under it.
local FACE_X, FACE_Y, FACE_R = 120, 74, 46
local HOUR_HAND, MINUTE_HAND = 26, 40

function Gen3WallClock:uiSize() return GBA_W, GBA_H end
function Gen3WallClock:wantsFillScale() return true end

function Gen3WallClock:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

-- The clock as the save keeps it: the chosen time, and when it was chosen.
function Gen3WallClock.read(save)
  local clock = save and save.gen3Clock
  if type(clock) ~= "table" then return nil end
  local elapsed = 0
  if clock.setAt and os and os.time then
    elapsed = math.max(0, os.time() - clock.setAt)
  end
  local minutes = (clock.hour or 0) * 60 + (clock.minute or 0)
                  + math.floor(elapsed / 60)
  return math.floor(minutes / 60) % 24, minutes % 60
end

function Gen3WallClock.new(game, opts)
  local self = setmetatable({}, Gen3WallClock)
  self.game = game
  self.onDone = opts and opts.onDone
  -- READING THE CLOCK IS NOT SETTING IT.  Emerald has two specials for the
  -- one face: StartWallClock, which walks you through hour, minute and a
  -- yes/no, and Special_ViewWallClock, which just shows the time.  Both come
  -- through here; `view` is the difference, and in view mode nothing the
  -- player presses may write save.gen3Clock.
  self.view = (opts and opts.view) or false
  -- opens on the save's time if it has one, so looking at the clock a second
  -- time shows what it is rather than midnight
  local hour, minute = Gen3WallClock.read(game.save)
  self.hour = hour or 12
  self.minute = minute or 0
  self.stage = "hour"                    -- hour, then minute, then confirm
  self.yes = true
  self.blink = 0
  return self
end

function Gen3WallClock:confirm()
  local save = self.game.save
  if save then
    save.gen3Clock = { hour = self.hour, minute = self.minute,
                       setAt = (os and os.time and os.time()) or nil }
  end
  self.game.stack:pop()
  if self.onDone then self.onDone(self.hour, self.minute) end
end

function Gen3WallClock:animate(dt)
  self.blink = (self.blink + 1) % 60
end

function Gen3WallClock:update(dt)
  self:animate(dt)
  local input = self.game.input
  if self.view then
    -- the cartridge's view is a look and a press to leave; A and B both do it
    if input:wasPressed("a") or input:wasPressed("b") then
      self.game.stack:pop()
      if self.onDone then self.onDone(self.hour, self.minute) end
    end
    return
  end
  if self.stage == "hour" then
    if input:wasPressed("up") then self.hour = (self.hour + 1) % 24
    elseif input:wasPressed("down") then self.hour = (self.hour - 1) % 24
    elseif input:wasPressed("a") then self.stage = "minute" end
  elseif self.stage == "minute" then
    if input:wasPressed("up") then self.minute = (self.minute + 1) % 60
    elseif input:wasPressed("down") then self.minute = (self.minute - 1) % 60
    elseif input:wasPressed("a") then self.stage = "confirm"
    elseif input:wasPressed("b") then self.stage = "hour" end
  else
    -- THE CONFIRM STEP IS A YES/NO, which is what the cartridge asks.  It was
    -- A-confirms / B-goes-back with the question printed under the box, and
    -- with the taller font that line fell off the bottom of the screen -- so
    -- the one moment the screen asks you something showed no question and no
    -- answer.
    if input:wasPressed("up") or input:wasPressed("down") then
      self.yes = not self.yes
    elseif input:wasPressed("a") then
      if self.yes == false then self.stage = "minute"; self.yes = true
      else return self:confirm() end
    elseif input:wasPressed("b") then
      self.stage = "minute"
      self.yes = true
    end
  end
end

-- 12-hour face with the meridiem beside it, which is how the cartridge reads
-- the time everywhere else.
function Gen3WallClock:clockText()
  local h = self.hour % 12
  if h == 0 then h = 12 end
  return ("%2d:%02d %s"):format(h, self.minute,
                                self.hour < 12 and "AM" or "PM")
end

local function hand(cx, cy, length, turns, width)
  local angle = turns * math.pi * 2 - math.pi / 2
  love.graphics.setLineWidth(width or 1)
  love.graphics.line(cx, cy, cx + math.cos(angle) * length,
                     cy + math.sin(angle) * length)
  love.graphics.setLineWidth(1)
end

-- THE FACE IS THE CARTRIDGE'S where the dataset has it.
--
-- The clock screen is a full-screen background, and the scene pass is blind
-- to it: that pass only records a layer whose loader it can also read a
-- palette load out of, and this one loads its two through a path the sweep
-- does not follow.  So this drew a circle with tick marks, which works and is
-- not the ROM.  The import finds the real face -- a sheet with two palettes
-- in front of it and the boy's and girl's 32x20 tilemaps behind, named beside
-- special 157's own callback -- and it is blitted here when it is there.
--
-- The HANDS stay drawn.  They are sprites on the cartridge and are not in the
-- background, so the shapes below are what moves over the real face until
-- those are extracted too.
function Gen3WallClock:faceImage()
  local record = (self.game and self.game.data.constants or {}).gen3WallClock
  if type(record) ~= "table" then return nil end
  local player = (self.game.save or {}).player or {}
  local which = (player.gender == "girl" and record.female) or record.male
                or record.female
  if not which then return nil end
  local ok, image = pcall(Assets.image, which)
  return ok and image or nil
end

function Gen3WallClock:draw()
  local face = self:faceImage()
  -- the cartridge's face is 256 wide against a 240 screen, so it sits eight
  -- pixels left of centre -- and the hands have to travel with it
  local originX = FACE_X
  if face then
    love.graphics.setColor(1, 1, 1, 1)
    local iw = face:getDimensions()
    local at = math.floor((GBA_W - iw) / 2)
    love.graphics.draw(face, at, 0)
    originX = FACE_X + at
  else
    love.graphics.setColor(0.13, 0.20, 0.35, 1)
    love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)

    -- the drawn face, for a dataset without the cartridge's
    love.graphics.setColor(0.96, 0.95, 0.88, 1)
    love.graphics.circle("fill", FACE_X, FACE_Y, FACE_R)
    love.graphics.setColor(0.28, 0.32, 0.44, 1)
    love.graphics.circle("line", FACE_X, FACE_Y, FACE_R)
    for tick = 0, 11 do
      local a = tick / 12 * math.pi * 2 - math.pi / 2
      local inner = FACE_R - (tick % 3 == 0 and 8 or 4)
      love.graphics.line(FACE_X + math.cos(a) * inner,
                         FACE_Y + math.sin(a) * inner,
                         FACE_X + math.cos(a) * (FACE_R - 2),
                         FACE_Y + math.sin(a) * (FACE_R - 2))
    end
  end

  -- the hands, with the one being set blinking so it is obvious which the
  -- d-pad is moving
  -- nothing blinks when you are only reading it: a blinking hand means "the
  -- d-pad is moving this one", and in view mode the d-pad moves nothing
  local showHour = self.view or self.stage ~= "hour" or self.blink < 40
  local showMinute = self.view or self.stage ~= "minute" or self.blink < 40
  love.graphics.setColor(0.20, 0.24, 0.36, 1)
  if showHour then
    hand(originX, FACE_Y, HOUR_HAND,
         ((self.hour % 12) + self.minute / 60) / 12, 3)
  end
  if showMinute then
    hand(originX, FACE_Y, MINUTE_HAND, self.minute / 60, 1)
  end
  love.graphics.circle("fill", originX, FACE_Y, 2)

  -- THE READING AND THE PROMPT, both inside the box.
  --
  -- The prompt used to be printed at y=152, one line below a box that ends at
  -- 160.  At eight pixels a glyph that was the last legible row on the screen;
  -- at Emerald's fifteen it is off the bottom, which is why the question at
  -- the one moment the screen asks one could not be read.  Both lines live in
  -- a box tall enough for them now.
  local BOX_TY, BOX_TH = 14, 6
  local glyphH = Font.glyphHeight()
  local inset = math.max(0, math.floor((16 - glyphH) / 2))
  Font.drawBox(6, BOX_TY, 18, BOX_TH)
  love.graphics.setColor(0, 0, 0, 1)
  local line1 = (BOX_TY + 1) * 8 + inset
  Font.draw(self:clockText(), 72, line1)
  if not self.view then
    local prompt = (self.stage == "hour" and Strings("SET THE HOUR"))
      or (self.stage == "minute" and Strings("SET THE MINUTE"))
      or Strings("IS THIS OK?")
    Font.draw(prompt, 60, line1 + 16)
  end
  love.graphics.setColor(1, 1, 1, 1)

  -- ...and the YES/NO the cartridge puts up once the time is chosen
  if self.stage == "confirm" and not self.view then
    local Theme = require("src.ui.Theme")
    local YES_TX, YES_TY = 24, 12
    Font.drawBox(YES_TX, YES_TY, 6, 6)
    love.graphics.setColor(0, 0, 0, 1)
    local rows = { Strings("YES"), Strings("NO") }
    for i, label in ipairs(rows) do
      local y = (YES_TY + 1 + (i - 1) * 2) * 8 + inset
      Font.draw(label, (YES_TX + 2) * 8, y)
      if (self.yes and i == 1) or (not self.yes and i == 2) then
        Font.drawCode(Theme.cursor, (YES_TX + 1) * 8, y)
      end
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return Gen3WallClock
