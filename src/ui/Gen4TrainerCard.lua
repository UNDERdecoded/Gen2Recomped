-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's TRAINER CASE (src/applications/trainer_case/{main,card_text,
-- sprites,badge_chimes}.c): the card on the top screen, the badge case on the
-- touch screen.
--
-- THE TOP SCREEN, back to front (`TrainerCaseApp_InitBackgrounds`):
--
--   SUB_1 (3)  case_top_screen -- the case around the card
--   SUB_2 (2)  the card face, trainer_card_front / _back (affine, 8bpp)
--   SUB_3 (0)  the trainer (lucas / dawn, a full-screen tilemap already
--              positioned), the eleven text windows, and on the back the
--              signature
--
-- THE TOUCH SCREEN (the MAIN engine -- GX_DISP_SELECT_SUB_MAIN): MAIN_2 (3)
-- the open badge case with its button, the badges and their sparkles as
-- sprites over it (OBJ priority 2 and 1), MAIN_3 (0) the lid over all of
-- them, and the button's press effect (OBJ priority 0) over the lid.
--
-- ALL OF IT IN PLATINUM'S COLOURS.  `TrainerCase_LoadCasePalette` writes the
-- version's sixteen case colours over row 0 of both BG palettes, last -- and
-- row 0 of the file every other picture is composed against is Diamond's
-- blue.  `gen4_trainer_card_art` (Gen4TrainerCardArt) composes every picture
-- against the palette the cartridge ends up with: the case is cream and gold.
-- `gen4_graphics`' `trainer_card/*` pictures are the fallback for a cache
-- that predates it, and are the Diamond-blue ones.
--
-- THE CARD LEVEL PAINTS THE STARS.  `TrainerCase_LoadCardPalette` swaps rows
-- 1-3 and 15 by `TrainerCase_CalculateTrainerCardLevel` (normal, cobalt,
-- bronze, silver, gold, black: 0..5 stars), and before the Pokedex the no-dex
-- palette instead -- which also hides the POKeDEX row's band, while
-- `TrainerCard_DrawFrontText` skips its text.
--
-- THE ROWS, `sTrainerCardWindowTemplates[]`: every window at tile x 2 and two
-- tiles high, so labels start at x 16; PARTIAL_WIDTH 17 tiles and FULL_WIDTH
-- 28 put a value's right edge at x 152 or x 240.  Front rows at tile y 4, 6,
-- 9, 12, 15, 18, 20 (IDNo., NAME, MONEY, POKeDEX, SCORE, TIME, ADVENTURE
-- STARTED); back rows at 2 (a four-tile window: date, then time 16 below), 7,
-- 9, 11.  Labels print at 0 and every value is right-aligned.
--
-- THE TIME IS LIVE, as on the cartridge's own card: hours padded to three,
-- two spaces, the minutes (`TrainerCard_Text_Format_HHMMWithoutColon`), and
-- the colon printed on its own at window x 205 -- shown fifteen frames, hidden
-- fifteen (`TrainerCase_UpdatePlayTime`).
--
-- TEXT COLOUR: TEXT_COLOR(1, 2, 0) on palette 15 of the card's NCLR, read
-- from the cache for THIS face (the black card's letter is yellow).
--
-- THE FLIP (`TrainerCase_FlipTrainerCard`, A): SUB_2 and SUB_3 -- the face
-- and everything printed on it -- scale in X about (128, 96); the case does
-- not.  Both scales start at 1 + 2/64 (the card lifts), X falls by 2/2^speed
-- with speed 8 counting down to 1 until it crosses 0 (then 36/4096), one
-- frame swaps the side, and X climbs back by 2/2^speed with speed counting up
-- to 8 until it reaches 1, when both snap to 1.  Here the face, portrait and
-- text are drawn into one 256x192 canvas and that is drawn scaled.
--
-- THE CASE.  `TrainerCaseApp_Main` is followed state for state: a tap on the
-- button rectangle {top 152, bottom 183, left 120, right 151} pushes the
-- button (`sButtonPushAnimData`: one frame half pressed, then fully), plays
-- the press effect (anim 10 at (96, 136), over the lid) and runs
-- `TrainerCase_OpenCloseBadgeCase`: the lid scales in Y about (128, 0) by the
-- fourteen speeds {2/64 x5, 2/32 x5, 2/16 x4}, down to 1/32 to open (the
-- cartridge leaves that five-row strip of lid at the top) and back to close.
-- The button springs back (`sButtonSpringBackAnimData`) when the touch
-- leaves it or lifts.  With the lid open the eight badge rectangles go live:
-- a tap chimes (`badge_chimes.c`: SEQ_SE_DP_BADGE_C pitched by badge and
-- polish), a held rub polishes (`TrainerCase_HandleBadgePolishing`: a step of
-- 3..40 px on one axis and at most 40 on the other counts once; every
-- sPolishThresholds[level] counted steps add one polish).  The rectangles'
-- extra test -- the MAIN_2 pixel under the touch must be the case's
-- background -- is approximated by the rectangle itself.
--
-- POLISH.  `game.save.badgePolish[i]` (1-based, Coal = 1) is the cartridge's
-- per-badge polish, 0..199; an obtained badge without an entry is at
-- BADGE_POLISH_THRESHOLD_NORMAL, 140, which is what obtaining one sets.
-- Levels: < 100 filthy, < 140 dirty, < 170 normal, < 190 two sparkles, else
-- four.  `TrainerCase_DrawBadgeDirt` loads row 3 - level of the badge's own
-- NCLR (row 0 for four sparkles) -- the `badge_<i>_<dirt>` pictures -- and the
-- sparkle sprites loop at `sSparkleCoordinates` (anim 8: four cells, eight
-- frames each; anim 9: four cells, four frames each).
--
-- THE SIGNATURE: 24x8 tiles at tile (4, 14) of SUB_3 on the back, the 1bpp
-- picture expanded to palette index 1 (`TrainerCase_ConvertSignature1BppTo8Bpp`
-- / `TrainerCase_DisplaySignature`) -- index 1 of the sub palette after the
-- case's row 0 is written, (115, 115, 115).  The back face's own art is the
-- white signature box with its ruled lines; the strokes go over it.  The port
-- keeps a signature at `game.save.player.signature` in either of two shapes:
--   * 64 strings of 192 characters, '1' for ink (row by row), or
--   * the cartridge's own 1536 bytes (a string, or a table of numbers):
--     tile-major over 24x8 tiles, eight bytes a tile, one byte a row, bit n =
--     pixel n from the left.
--
-- WHAT THE PORT CANNOT FILL IN, named rather than faked: SCORE (no
-- `GameRecords_GetTrainerScore`) prints 0; ADVENTURE STARTED and the whole
-- back are records the save does not keep, so they print the cartridge's own
-- blanks and zeroes; nothing writes a signature yet (the cartridge's signing
-- screen is src/applications/signature.c, not this one), so the box is empty
-- unless a save carries one; polish does not dull day by day as the
-- cartridge's does; and of the five card-level conditions only the Hall of
-- Fame one is recorded.
--
-- PAGES.  With the touch screen shown this is the cartridge's own screen: A
-- flips front <-> back (animated), the case opens and closes by its button
-- (SELECT does the same, so it is reachable without touch), B leaves.
-- Without it, A walks front -> back (animated) -> badge case -> front on the
-- one screen there is, and B steps back to the front first.

local Badges = require("src.inventory.Badges")
local Font = require("src.render.Font")
local Gen4Palettes = require("src.render.Gen4Palettes")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")

local Gen4TrainerCard = {}
Gen4TrainerCard.__index = Gen4TrainerCard
Gen4TrainerCard.isOpaque = true

local W, H = 256, 192
local floor = math.floor

-- WHERE THE BADGES GO: `sBadgeCoordinates` (sprites.c), each the anchor of a
-- 64x64 cell with no OAM offset.  The second row's anchor is y 72 although
-- its sockets, touch rectangles and sparkles are at y 96 -- because those
-- four cells carry their art 24 rows lower inside the 64x64 than the first
-- row's do.  Moving the anchor to "match the sockets" puts them 24 low; that
-- was tried and looked at.
local BADGE_AT = {
  { 24, 40 }, { 80, 40 }, { 136, 40 }, { 192, 40 },
  { 24, 72 }, { 80, 72 }, { 136, 72 }, { 192, 72 },
}
-- `sSparkleCoordinates`: the same, with the second row at its sockets' y 96
local SPARKLE_AT = {
  { 24, 40 }, { 80, 40 }, { 136, 40 }, { 192, 40 },
  { 24, 96 }, { 80, 96 }, { 136, 96 }, { 192, 96 },
}

-- `sTouchRectangles_BadgesEnabled`, { top, bottom, left, right }, inclusive.
-- Index 0 is the button; 1..8 the badges, live only with the lid open.
local TOUCH_BUTTON = 0
local TOUCH_RECTS = {
  [0] = { 152, 183, 120, 151 },
  { 40, 79, 24, 63 }, { 40, 79, 80, 119 }, { 40, 79, 136, 167 }, { 40, 79, 192, 231 },
  { 96, 135, 24, 63 }, { 96, 135, 80, 119 }, { 96, 135, 136, 167 }, { 96, 135, 192, 231 },
}

-- `sBadgeCaseCoverScalingSpeeds`
local LID_SPEEDS = {
  2 / 64, 2 / 64, 2 / 64, 2 / 64, 2 / 64,
  2 / 32, 2 / 32, 2 / 32, 2 / 32, 2 / 32,
  2 / 16, 2 / 16, 2 / 16, 2 / 16,
}

-- the button's three faces and `sButtonPushAnimData` / `sButtonSpringBackAnimData`
-- ({ duration, face } pairs, a zero duration ends)
local BUTTON_NOT, BUTTON_HALF, BUTTON_FULLY = 0, 1, 2
local BUTTON_PUSH = { 1, BUTTON_HALF, 0, BUTTON_FULLY }
local BUTTON_SPRING = { 1, BUTTON_HALF, 0, BUTTON_NOT }
local BUTTON_DEFAULT, BUTTON_PUSHED, BUTTON_SPRING_BACK = 0, 1, 2
-- `TrainerCase_RedrawBadgeCaseButton`: tile (14, 19) of MAIN_2
local BUTTON_X, BUTTON_Y = 14 * 8, 19 * 8
-- the press effect, BADGE_CASE_ANIM_BUTTON_PRESS_EFFECT: cells 16..19 two
-- frames each, once; the fourth cell is empty
local EFFECT_X, EFFECT_Y = 96, 136
local EFFECT_FRAMES, EFFECT_TICKS = 3, 2
-- the sparkles: anim 8 eight frames a cell, anim 9 four; four cells, looping
local SPARKLE_CELLS = 4
local TWO_SPARKLE_TICKS, FOUR_SPARKLE_TICKS = 8, 4

-- polish, trainer_case.h
local POLISH_DIRTY, POLISH_NORMAL, POLISH_2_SPARKLES, POLISH_4_SPARKLES = 100, 140, 170, 190
local MAX_POLISH = 199
local LEVEL_FILTHY, LEVEL_DIRTY, LEVEL_NORMAL, LEVEL_2_SPARKLES, LEVEL_4_SPARKLES = 0, 1, 2, 3, 4
-- `sPolishThresholds`, by level
local POLISH_STEPS = { [0] = 1, 3, 4, 15, 15 }
-- `sBadgeChimeBasePitches`, 1/64 semitone
local CHIME_PITCH = { 0, 128, 256, 320, 448, 576, 704, 768 }

-- the signature: 24x8 tiles at tile (4, 14), ink = sub palette entry 1
local SIG_X, SIG_Y, SIG_W, SIG_H = 4 * 8, 14 * 8, 24 * 8, 8 * 8
local SIG_INK = { 115 / 255, 115 / 255, 115 / 255 }

-- THE CARD'S OWN SLOTS, out of `sTrainerCardWindowTemplates[]`.
local LABEL_X = 16
local PARTIAL_RIGHT = 16 + 17 * 8
local FULL_RIGHT = 16 + 28 * 8
local FRONT_Y = { id = 32, name = 48, money = 72, dex = 96,
                  score = 120, time = 144, started = 160 }
local BACK_Y = { hof = 16, hofTime = 32, linked = 56, battles = 72, trades = 88 }
-- The link-battle row: W at tile 14, L at tile 22, the wins right-aligned
-- eight tiles short of the edge and the losses at the edge.
local WINS_LABEL_X = 16 + 14 * 8
local WINS_RIGHT = FULL_RIGHT - 8 * 8
local LOSSES_LABEL_X = 16 + 22 * 8
-- `TrainerCard_BlinkPlaytimeColon`: the colon at window x 205.
local COLON_X = 16 + 205
local BLINK = 30

-- TEXT_COLOR(1, 2, 0) on palette 15; the fallback for a cache without
-- palettes (the cartridge's own rounding: 20 of 31 is 165, not 164).
local INK = { { 74 / 255, 74 / 255, 74 / 255 },
              { 165 / 255, 165 / 255, 165 / 255 } }
local INK_SLOT, INK_LETTER, INK_SHADOW = 15, 1, 2

-- The money sign has one owner (see tools/gen4_money_window_check.lua).
local function moneySign()
  return require("src.core.GameVersion").moneySign()
end

-- The cartridge's own blanks, `TrainerCard_Text_BlankDate` and the pair of
-- `TrainerCard_Text_TwoDashes` the HoF time is built from.
local BLANK_DATE = "--- --, ----"
local BLANK_TIME = "--:--"

-- The faces, in TRAINER_CARD_LEVEL order, and the no-dex face.
local LEVEL_NAME = { [0] = "normal", "cobalt", "bronze", "silver", "gold", "black" }
local NO_DEX = "no_dex"
-- the older cache's suffixes for the same faces
local LEGACY_SUFFIX = { normal = "", cobalt = "_cobalt", bronze = "_bronze", silver = "_silver",
                        gold = "_gold", black = "_black", no_dex = "_no_dex" }

local PAGE_FRONT, PAGE_BACK, PAGE_CASE = 1, 2, 3
Gen4TrainerCard.PAGE_FRONT, Gen4TrainerCard.PAGE_BACK, Gen4TrainerCard.PAGE_CASE = PAGE_FRONT, PAGE_BACK, PAGE_CASE

-- `TrainerCase_GetPlayerInput`'s answers
local INPUT_NONE, INPUT_TAP, INPUT_HOLD, INPUT_A, INPUT_B, INPUT_SELECT = 0, 1, 2, 3, 4, 5

-- The fallback frame, used only when the cache carries no card art at all.
local CARD = { tx = 1, ty = 1, tw = 30, th = 15 }
local FALLBACK_LABEL_X = 24
local FALLBACK_VALUE_X = 150
local FALLBACK_FIRST_ROW = 30
local FALLBACK_ROW_PITCH = 18

function Gen4TrainerCard:uiSize() return W, H end
function Gen4TrainerCard:wantsFillScale() return true end
function Gen4TrainerCard:wantsEdgeBleed() return false end

function Gen4TrainerCard:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(W / 8) - 1, math.ceil(H / 8) - 1) }
end

function Gen4TrainerCard.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4TrainerCard)
  self.game = game
  self.onCancel = opts.onCancel
  self.page = PAGE_FRONT
  self.t = 0
  self.cache = {}
  local data = game.data or {}
  self.art = (data.gen4_graphics or {}).screens or {}
  self.cardArt = data.gen4_trainer_card_art or {}
  if not next(self.cardArt) then
    Logger.warn("gen4 trainer card: this cache carries no gen4_trainer_card_art -- "
                .. "the case is drawn in the generic (Diamond-blue) palette; "
                .. "run tools/gen4_art_extract trainer_card")
  end
  self.face = self:faceName()
  self.inkPair = Gen4Palettes.text(game.data,
                                   "trainer_card/trainer_card_front" .. (LEGACY_SUFFIX[self.face] or ""),
                                   INK_SLOT, INK_LETTER, INK_SHADOW)
  if not (self.cardArt["front_" .. self.face] or self.art["trainer_card/trainer_card_front"]) then
    Logger.warn("gen4 trainer card: this cache carries no card face -- "
                .. "re-import to get Platinum's own card")
  end

  -- `TrainerCaseApp_Init`'s state
  self.state = "main"            -- main | flip | lid
  self.flip = nil                -- { sub, speed, x, y } while flipping
  self.lidOpen = false           -- badgeCaseOpenState
  self.lidScale = 1              -- badgeCaseCoverYScale
  self.lidSub, self.lidIndex, self.coverMoving = nil, 0, false
  self.buttonFace = BUTTON_NOT
  self.buttonState = BUTTON_DEFAULT
  self.buttonPushed = false
  self.buttonAnimIndex, self.buttonAnimTimer = 0, 0
  self.effectT = nil             -- the press effect's tick, nil when not shown
  self.polishProgress = { 0, 0, 0, 0, 0, 0, 0, 0 }
  self.polishSfx = { px = 0, py = 0, cx = 0, cy = 0, index = 0 }
  self.polishingEnabled = false
  -- the pointer: who holds it, where it is now, the press not yet read, and
  -- where it was when polishing last looked
  self.pointer, self.touchAt, self.tapAt, self.lastTouch = nil, nil, nil, nil
  return self
end

function Gen4TrainerCard:female()
  local player = (self.game.save or {}).player or {}
  local g = player.gender
  return g == "girl" or g == "female" or g == 1
end

local function loadImage(self, path)
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

-- a `gen4_graphics` screen picture
function Gen4TrainerCard:img(key)
  local rec = self.art[key]
  return loadImage(self, (type(rec) == "table" and rec.path) or rec)
end

-- a `gen4_trainer_card_art` picture, and its record
function Gen4TrainerCard:cardImg(key)
  local rec = self.cardArt[key]
  if type(rec) ~= "table" then return nil end
  return loadImage(self, rec.path), rec
end

-- Two tones: naming both leaves the shadow where the cartridge put it.
function Gen4TrainerCard:ink()
  local pair = self.inkPair or INK
  Font.pushStyle({ text = pair[1], shadow = pair[2] })
end

function Gen4TrainerCard:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

local function sfx(self, name, pitch)
  local data = self.game and self.game.data
  if not data then return end
  local ok, Sound = pcall(require, "src.core.Sound")
  if not (ok and type(Sound) == "table" and Sound.play) then return end
  local okP, src = pcall(Sound.play, data, name)
  if okP and pitch and type(src) == "userdata" and src.setPitch then pcall(src.setPitch, src, pitch) end
end

-- ------------------------------------------------------------- the loop --

function Gen4TrainerCard:update()
  self.t = (self.t or 0) + 1
  local shown = self:subscreenShown()
  if self.state == "flip" then
    if self:flipStep() then self.state = "main" end
  elseif self.state == "lid" then
    self:lidState()
  elseif shown then
    self:mainState()
  else
    self:singleScreenState()
  end
  self:buttonAnimation()
  if self.effectT then self.effectT = self.effectT + 1 end
  -- a press is news for one frame only, as `gSystem.touchPressed` is
  self.tapAt = nil
end

-- `TrainerCase_GetPlayerInput`.  `self.touched` is the rectangle under the
-- press (a tap) or the held touch, nil for none.
function Gen4TrainerCard:readInput()
  self.touched = nil
  local pressed = self.tapAt
  self.tapAt = nil
  if pressed then self.polishingEnabled = true end
  local touch = false
  if pressed then
    local idx = self:rectAt(pressed.x, pressed.y)
    if idx then self.touched = idx; return INPUT_TAP end
  end
  if self.touchAt then
    self.touched = self:rectAt(self.touchAt.x, self.touchAt.y)
    if self.polishingEnabled then touch = true end
  else
    self.polishingEnabled = false
  end
  if touch then return INPUT_HOLD end
  local input = self.game.input
  if input then
    if input:wasPressed("a") then return INPUT_A end
    if input:wasPressed("b") or input:wasPressed("start") then return INPUT_B end
    if input:wasPressed("select") then return INPUT_SELECT end
  end
  return INPUT_NONE
end

-- which rectangle (0 the button, 1..8 a badge) holds the point; the badges
-- only with the lid open
function Gen4TrainerCard:rectAt(x, y)
  local last = self.lidOpen and 8 or 0
  for i = 0, last do
    local r = TOUCH_RECTS[i]
    if y >= r[1] and y <= r[2] and x >= r[3] and x <= r[4] then return i end
  end
  return nil
end

function Gen4TrainerCard:pushButton(withEffect)
  self.buttonPushed = true
  self.buttonState = BUTTON_PUSHED
  self.buttonAnimIndex, self.buttonAnimTimer = 0, 0
  if withEffect then self.effectT = 0 end
end

function Gen4TrainerCard:springButton()
  self.buttonPushed = false
  self.buttonState = BUTTON_SPRING_BACK
end

-- TRAINER_CASE_STATE_MAIN, with the touch screen shown
function Gen4TrainerCard:mainState()
  local input = self:readInput()
  if input == INPUT_TAP then
    if self.touched == TOUCH_BUTTON then
      self:startLid()
    else
      local badge = self.touched
      if self:earned()[badge] then self:chime(badge) end
    end
  elseif input == INPUT_HOLD then
    if self.buttonPushed and self.touched ~= TOUCH_BUTTON then self:springButton() end
    self:handlePolishing()
  else
    if self.buttonPushed and self.buttonState == BUTTON_DEFAULT then self:springButton() end
    self:resetPolishSfx()
    if input == INPUT_A then
      if self.page == PAGE_CASE then self.page = PAGE_FRONT end
      self:startFlip()
    elseif input == INPUT_B then
      self:close()
    elseif input == INPUT_SELECT then
      -- the port's key path to the button
      self:startLid()
    end
  end
end

-- without the touch screen: the case is a page of the one screen
function Gen4TrainerCard:singleScreenState()
  local input = self.game.input
  if not input then return end
  if input:wasPressed("a") then
    if self.page == PAGE_FRONT then
      self:startFlip()
    else
      self.page = self.page % PAGE_CASE + 1
    end
  elseif input:wasPressed("b") or input:wasPressed("start") then
    if self.page ~= PAGE_FRONT then self.page = PAGE_FRONT else self:close() end
  end
end

-- ------------------------------------------------------------ the flip --

function Gen4TrainerCard:startFlip()
  self.state = "flip"
  self.flip = { sub = "initial" }
  self:flipStep()
end

-- `TrainerCase_FlipTrainerCard`, one frame; true when done
function Gen4TrainerCard:flipStep()
  local f = self.flip
  if not f then return true end
  if f.sub == "initial" then
    f.speed = 8
    f.x, f.y = 1 + 2 / 64, 1 + 2 / 64
    sfx(self, "SEQ_SE_DP_CARD5")
    f.sub = "down"
  elseif f.sub == "down" then
    f.x = f.x - 2 / 2 ^ f.speed
    if f.x <= 0 then
      f.x = 36 / 4096
      f.sub = "swap"
    end
    f.speed = math.max(1, f.speed - 1)
  elseif f.sub == "swap" then
    self.page = (self.page == PAGE_BACK) and PAGE_FRONT or PAGE_BACK
    f.sub = "up"
  elseif f.sub == "up" then
    f.speed = math.min(8, f.speed + 1)
    f.x = f.x + 2 / 2 ^ f.speed
    if f.x >= 1 then
      self.flip = nil
      return true
    end
  end
  return false
end

-- the card layer's scale now: x, y
function Gen4TrainerCard:cardScale()
  local f = self.flip
  if not (f and f.x) then return 1, 1 end
  return f.x, f.y
end

-- ------------------------------------------------------------- the lid --

function Gen4TrainerCard:startLid()
  self:pushButton(true)
  self.lidSub = "initial"
  self.coverMoving = false
  self.state = "lid"
end

-- TRAINER_CASE_STATE_OPEN_CLOSE_BADGE_CASE
function Gen4TrainerCard:lidState()
  if self.buttonState == BUTTON_DEFAULT then
    local input = self:readInput()
    if input == INPUT_TAP then
      if self.touched == TOUCH_BUTTON then self:pushButton(false) end
    elseif input == INPUT_HOLD then
      if self.buttonPushed and self.touched ~= TOUCH_BUTTON then self:springButton() end
    elseif self.buttonPushed then
      self:springButton()
    end
  end
  if not self.coverMoving then self.coverMoving = self:lidStep() end
  if self.coverMoving then
    self.coverMoving = false
    self.state = "main"
  end
end

-- `TrainerCase_OpenCloseBadgeCase`, one frame; true when done
function Gen4TrainerCard:lidStep()
  local n = #LID_SPEEDS
  if self.lidSub == "initial" then
    self.lidIndex = 0
    if not self.lidOpen then
      self.lidScale = 1
      self.lidSub = "open"
    else
      self.lidSub = "close"
    end
    sfx(self, "SEQ_SE_DP_CARD11")
  elseif self.lidSub == "open" then
    self.lidIndex = self.lidIndex + 1
    self.lidScale = self.lidScale - LID_SPEEDS[self.lidIndex]
    if self.lidIndex == n then
      self.lidOpen = true
      self.lidSub = "done"
    end
  elseif self.lidSub == "close" then
    self.lidScale = self.lidScale + LID_SPEEDS[n - self.lidIndex]
    self.lidIndex = self.lidIndex + 1
    if self.lidIndex == n then
      self.lidOpen = false
      self.lidScale = 1
      self.lidSub = "done"
    end
  else
    return true
  end
  return false
end

-- the lid shown at once, open or closed (for a caller or a harness)
function Gen4TrainerCard:setLid(open)
  self.lidOpen = open and true or false
  local s = 1
  if open then for _, v in ipairs(LID_SPEEDS) do s = s - v end end
  self.lidScale = s
end

-- ---------------------------------------------------------- the button --

-- `TrainerCase_HandleBadgeCaseButtonAnimation`
function Gen4TrainerCard:buttonAnimation()
  if self.buttonState == BUTTON_PUSHED then
    if self:animateButton(BUTTON_PUSH) then self.buttonState = BUTTON_DEFAULT end
  elseif self.buttonState == BUTTON_SPRING_BACK then
    if self:animateButton(BUTTON_SPRING) then self.buttonState = BUTTON_DEFAULT end
  end
end

-- `TrainerCase_AnimateBadgeCaseButton`
function Gen4TrainerCard:animateButton(data)
  local duration = data[self.buttonAnimIndex * 2 + 1]
  if duration == 0 then
    self.buttonAnimTimer, self.buttonAnimIndex = 0, 0
    return true
  elseif self.buttonAnimTimer >= duration then
    self.buttonAnimTimer = 0
    self.buttonAnimIndex = self.buttonAnimIndex + 1
  end
  if self.buttonAnimTimer == 0 then self.buttonFace = data[self.buttonAnimIndex * 2 + 2] end
  self.buttonAnimTimer = self.buttonAnimTimer + 1
  return false
end

-- ------------------------------------------------------------- polish --

function Gen4TrainerCard:polish(badge)
  local save = self.game.save or {}
  local v = type(save.badgePolish) == "table" and tonumber(save.badgePolish[badge]) or nil
  if not v then return POLISH_NORMAL end
  return math.max(0, math.min(MAX_POLISH, floor(v)))
end

function Gen4TrainerCard:setPolish(badge, value)
  local save = self.game.save
  if type(save) ~= "table" then return end
  if type(save.badgePolish) ~= "table" then save.badgePolish = {} end
  save.badgePolish[badge] = math.max(0, math.min(MAX_POLISH, floor(value)))
end

-- `TrainerCase_GetBadgePolishLevel`
function Gen4TrainerCard.polishLevel(polish)
  if polish < POLISH_DIRTY then return LEVEL_FILTHY end
  if polish < POLISH_NORMAL then return LEVEL_DIRTY end
  if polish < POLISH_2_SPARKLES then return LEVEL_NORMAL end
  if polish < POLISH_4_SPARKLES then return LEVEL_2_SPARKLES end
  return LEVEL_4_SPARKLES
end

-- the badge palette row `TrainerCase_DrawBadgeDirt` is given
function Gen4TrainerCard.dirtRow(level)
  if level >= LEVEL_4_SPARKLES then return 0 end
  return LEVEL_2_SPARKLES - level
end

-- `TrainerCase_HandleBadgePolishing`, once a frame while held
function Gen4TrainerCard:handlePolishing()
  local cur, last = self.touchAt, self.lastTouch
  local badge = self.touched
  if cur and last and badge and badge ~= TOUCH_BUTTON and self:earned()[badge] then
    local s = self.polishSfx
    local valid = false
    local dx = math.abs(last.x - cur.x)
    s.cx = (last.x > cur.x) and -1 or 1
    if dx >= 3 and dx <= 40 then
      local dy = math.abs(last.y - cur.y)
      s.cy = (last.y > cur.y) and -1 or 1
      if dy <= 40 then valid = true; self:polishSound() else s.cx, s.cy = 0, 0 end
    elseif dx <= 40 then
      local dy = math.abs(last.y - cur.y)
      s.cy = (last.y > cur.y) and -1 or 1
      if dy >= 3 and dy <= 40 then valid = true; self:polishSound() else s.cx, s.cy = 0, 0 end
    end
    if valid then self:polishBadge(badge) end
  end
  self.lastTouch = cur and { x = cur.x, y = cur.y } or nil
end

-- `TrainerCase_PolishBadge`
function Gen4TrainerCard:polishBadge(badge)
  local polish = self:polish(badge)
  if polish + 1 > MAX_POLISH then return end
  local level = Gen4TrainerCard.polishLevel(polish)
  self.polishProgress[badge] = (self.polishProgress[badge] or 0) + 1
  if self.polishProgress[badge] >= POLISH_STEPS[level] then
    self.polishProgress[badge] = 0
    self:setPolish(badge, polish + 1)
  end
end

-- `TrainerCase_PlayPolishingSoundEffects`
function Gen4TrainerCard:polishSound()
  local s = self.polishSfx
  if s.px == 0 and s.py == 0 then sfx(self, "SEQ_SE_DP_MIGAKU01") end
  if s.px * s.cx < 0 or s.py * s.cy < 0 then
    s.index = (s.index + 1) % 2
    sfx(self, s.index == 0 and "SEQ_SE_DP_MIGAKU01" or "SEQ_SE_DP_MIGAKU02")
  end
  s.px, s.py, s.cx, s.cy = s.cx, s.cy, 0, 0
end

function Gen4TrainerCard:resetPolishSfx()
  local s = self.polishSfx
  s.px, s.py, s.cx, s.cy, s.index = 0, 0, 0, 0, 0
end

-- `TrainerCase_PlayBadgeChime`: SEQ_SE_DP_BADGE_C at the badge's pitch, a
-- duller badge 152/64 semitones lower per level below four sparkles
function Gen4TrainerCard:chime(badge)
  local level = Gen4TrainerCard.polishLevel(self:polish(badge))
  local pitch = (CHIME_PITCH[badge] or 0) - 152 * (LEVEL_4_SPARKLES - level)
  sfx(self, "SEQ_SE_DP_BADGE_C", 2 ^ (pitch / 768))
end

-- ------------------------------------------------------------ pointer --

-- A touch on the shown bottom screen belongs to the case, all of it.
function Gen4TrainerCard:touchpressed(id, px, py)
  local shown, SS = self:subscreenShown()
  if not shown or not SS.toLocal then return false end
  local x, y = SS.toLocal(self.game, px, py)
  if not x then return (self.game and self.game.secondScreenInjecting) and true or false end
  if self.pointer ~= nil then return true end
  self.pointer = id
  x, y = floor(x), floor(y)
  self.tapAt = { x = x, y = y }
  self.touchAt = { x = x, y = y }
  return true
end

function Gen4TrainerCard:touchmoved(id, px, py)
  if self.pointer ~= id then return false end
  local shown, SS = self:subscreenShown()
  local x, y
  if shown and SS.toLocal then x, y = SS.toLocal(self.game, px, py) end
  if x then self.touchAt = { x = floor(x), y = floor(y) } end
  return true
end

function Gen4TrainerCard:touchreleased(id)
  if self.pointer ~= id then return false end
  self.pointer, self.touchAt, self.lastTouch = nil, nil, nil
  return true
end

-- ------------------------------------------------------------- the card --

-- HOW MANY OF THE FIVE `TrainerCase_CalculateTrainerCardLevel` counts this
-- save has: the game completed, the national dex completed, a 100-win Battle
-- Tower streak, contest master in any rank, the Underground flag.  The port
-- records only the first; the other four are named so "not implemented" is
-- not mistaken for "not earned".
function Gen4TrainerCard:cardLevel()
  local save = self.game.save or {}
  local level = 0
  local hof = save.hallOfFame
  if type(hof) == "table" and #hof > 0 then level = level + 1 end
  -- national dex completed  -- no port equivalent
  -- Battle Tower 100 streak -- no port equivalent
  -- contest master          -- no port equivalent
  -- Underground base flag   -- no port equivalent
  return level
end

-- Which face: the no-dex one wins outright, whatever the level.
function Gen4TrainerCard:faceName()
  if not self:hasPokedex() then return NO_DEX end
  return LEVEL_NAME[self:cardLevel()] or "normal"
end

-- kept for callers that ask for the old suffix
function Gen4TrainerCard:faceSuffix()
  return LEGACY_SUFFIX[self:faceName()] or ""
end

function Gen4TrainerCard:hasPokedex()
  local ok, Flags = pcall(require, "src.script.Flags")
  if not (ok and Flags and Flags.hasPokedex) then return true end
  return Flags.hasPokedex(self.game.save) and true or false
end

function Gen4TrainerCard:playSeconds()
  local ok, SaveData = pcall(require, "src.core.SaveData")
  if ok and SaveData and SaveData.playSeconds then
    return floor(SaveData.playSeconds(self.game.save or {}) or 0)
  end
  return 0
end

-- The front's rows, in the cartridge's own order, each as
-- { label, value, y, right edge }.
function Gen4TrainerCard:frontRows()
  local save = self.game.save or {}
  local player = save.player or {}

  local seen = 0
  for _ in pairs((save.pokedex or {}).seen or {}) do seen = seen + 1 end

  local seconds = self:playSeconds()
  local hours = math.min(999, floor(seconds / 3600))
  local id = floor(tonumber(player.id) or 0) % 65536

  local rows = {
    { Strings("IDNo."), ("%05d"):format(id), FRONT_Y.id, PARTIAL_RIGHT },
    { Strings("NAME"), tostring(player.name or Strings("PLAYER")),
      FRONT_Y.name, PARTIAL_RIGHT },
    { Strings("MONEY"), moneySign() .. tostring(floor(save.money or 0)),
      FRONT_Y.money, PARTIAL_RIGHT },
  }
  if self:hasPokedex() then
    rows[#rows + 1] = { Strings("POKéDEX"), tostring(seen),
                        FRONT_Y.dex, PARTIAL_RIGHT }
  end
  rows[#rows + 1] = { Strings("SCORE"), "0", FRONT_Y.score, PARTIAL_RIGHT }
  -- hours padded to three, TWO spaces where the blinking colon goes
  rows[#rows + 1] = {
    Strings("TIME"),
    ("%3d  %02d"):format(hours, floor(seconds / 60) % 60),
    FRONT_Y.time, FULL_RIGHT,
  }
  rows[#rows + 1] = { Strings("ADVENTURE STARTED"), BLANK_DATE,
                      FRONT_Y.started, FULL_RIGHT }
  return rows
end

function Gen4TrainerCard:colonShown()
  local t = self.t or 0
  return t == 0 or (t % BLINK) >= BLINK / 2
end

-- The back's rows: every value is a record the port does not keep.
function Gen4TrainerCard:backRows()
  return {
    { Strings("HALL OF FAME DEBUT"), BLANK_DATE, BACK_Y.hof, FULL_RIGHT },
    { false, BLANK_TIME, BACK_Y.hofTime, FULL_RIGHT },
    { Strings("TIMES LINKED"), "0", BACK_Y.linked, FULL_RIGHT },
    { Strings("LINK TRADES"), "0", BACK_Y.trades, FULL_RIGHT },
  }
end

local function row(label, value, y, right)
  if label then Font.draw(label, LABEL_X, y) end
  if value then Font.draw(value, right - Font.width(value), y) end
end

-- SUB_1: the case around the card
function Gen4TrainerCard:drawCase()
  local g = love.graphics
  local case = self:cardImg("case_top")
  g.setColor(1, 1, 1, 1)
  if case then g.draw(case, 0, 0) end
  return case ~= nil
end

-- SUB_2: one face of the card
function Gen4TrainerCard:faceImage(side)
  return self:cardImg(side .. "_" .. self.face)
      or self:img("trainer_card/trainer_card_" .. side .. (LEGACY_SUFFIX[self.face] or ""))
      or self:img("trainer_card/trainer_card_" .. side)
end

-- The signature as the save carries it: a 192x64 table of rows of booleans,
-- or nil.  See the header for the two accepted shapes.
function Gen4TrainerCard:signaturePixels()
  local player = (self.game.save or {}).player or {}
  local sig = player.signature
  if sig == nil then return nil end
  local px = {}
  for y = 1, SIG_H do px[y] = {} end
  local any = false
  if type(sig) == "table" and type(sig[1]) == "string" then
    for y = 1, SIG_H do
      local line = sig[y] or ""
      for x = 1, SIG_W do
        if line:sub(x, x) == "1" then px[y][x] = true; any = true end
      end
    end
  else
    local function byteAt(i)
      if type(sig) == "string" then return sig:byte(i) or 0 end
      if type(sig) == "table" then return tonumber(sig[i]) or 0 end
      return 0
    end
    for y = 0, SIG_H - 1 do
      for x = 0, SIG_W - 1 do
        local tile = floor(y / 8) * (SIG_W / 8) + floor(x / 8)
        local b = byteAt(tile * 8 + y % 8 + 1)
        if floor(b / 2 ^ (x % 8)) % 2 == 1 then px[y + 1][x + 1] = true; any = true end
      end
    end
  end
  return any and px or nil
end

function Gen4TrainerCard:signatureImage()
  if self.sigImage == nil then
    self.sigImage = false
    local px = self:signaturePixels()
    if px and love.image then
      local ok, data = pcall(love.image.newImageData, SIG_W, SIG_H)
      if ok and data then
        for y = 1, SIG_H do
          for x = 1, SIG_W do
            if px[y][x] then data:setPixel(x - 1, y - 1, SIG_INK[1], SIG_INK[2], SIG_INK[3], 1) end
          end
        end
        local okI, img = pcall(love.graphics.newImage, data)
        if okI and img then img:setFilter("nearest", "nearest"); self.sigImage = img end
      end
    end
  end
  return self.sigImage or nil
end

-- SUB_2 + SUB_3 of one side, unscaled: the face, then the trainer and the
-- text (front) or the text and the signature (back).  False when the cache
-- has no face.
function Gen4TrainerCard:drawCardLayer(side)
  local g = love.graphics
  local face = self:faceImage(side)
  if not face then return false end
  g.setColor(1, 1, 1, 1)
  g.draw(face, 0, 0)
  self:ink()
  if side == "front" then
    local who = self:female() and "dawn" or "lucas"
    local portrait = self:cardImg(who) or self:img("trainer_card/" .. who)
    if portrait then g.draw(portrait, 0, 0) end
    for _, r in ipairs(self:frontRows()) do row(r[1], r[2], r[3], r[4]) end
    if self:colonShown() then Font.draw(":", COLON_X, FRONT_Y.time) end
  else
    for _, r in ipairs(self:backRows()) do row(r[1], r[2], r[3], r[4]) end
    Font.draw(Strings("LINK BATTLES"), LABEL_X, BACK_Y.battles)
    Font.draw(Strings("W"), WINS_LABEL_X, BACK_Y.battles)
    Font.draw("0", WINS_RIGHT - Font.width("0"), BACK_Y.battles)
    Font.draw(Strings("L"), LOSSES_LABEL_X, BACK_Y.battles)
    Font.draw("0", FULL_RIGHT - Font.width("0"), BACK_Y.battles)
  end
  Font.popStyle()
  g.setColor(1, 1, 1, 1)
  if side == "back" then
    local sig = self:signatureImage()
    if sig then g.draw(sig, SIG_X, SIG_Y) end
  end
  return true
end

-- one side, with the case behind it, scaled by the flip if one is running
function Gen4TrainerCard:drawSide(side)
  local g = love.graphics
  if not self:faceImage(side) then return self:drawFallbackFace() end
  self:drawCase()
  local sx, sy = self:cardScale()
  if sx == 1 and sy == 1 then
    self:drawCardLayer(side)
    return
  end
  -- SUB_2 and SUB_3 scale together about (128, 96): render them as one
  local okC = pcall(function()
    if not self.flipCanvas then
      self.flipCanvas = g.newCanvas(W, H)
      self.flipCanvas:setFilter("nearest", "nearest")
    end
  end)
  if not okC or not self.flipCanvas then
    self:drawCardLayer(side)
    return
  end
  local prev = g.getCanvas()
  g.push("all")
  g.origin()
  g.setScissor()
  g.setCanvas(self.flipCanvas)
  g.clear(0, 0, 0, 0)
  self:drawCardLayer(side)
  g.pop()
  if g.getCanvas() ~= prev then g.setCanvas(prev) end
  g.push("all")
  g.setColor(1, 1, 1, 1)
  g.setBlendMode("alpha", "premultiplied")
  g.draw(self.flipCanvas, W / 2, H / 2, 0, sx, sy, W / 2, H / 2)
  g.pop()
end

function Gen4TrainerCard:drawFace() return self:drawSide("front") end
function Gen4TrainerCard:drawBack() return self:drawSide("back") end

-- This port's own card, drawn only when the cache has no face to draw.
function Gen4TrainerCard:drawFallbackFace()
  Font.drawBox(CARD.tx, CARD.ty, CARD.tw, CARD.th)
  local title = Strings("TRAINER CARD")
  Font.draw(title, floor((W - Font.width(title)) / 2), 14)

  local y = FALLBACK_FIRST_ROW
  for _, r in ipairs(self:frontRows()) do
    if r[1] then Font.draw(r[1], FALLBACK_LABEL_X, y) end
    Font.draw(r[2], FALLBACK_VALUE_X, y)
    y = y + FALLBACK_ROW_PITCH
  end
end

-- How many badges this save has, and which, in the dataset's own order.
function Gen4TrainerCard:earned()
  local out = {}
  for i, entry in ipairs(Badges.list(self.game.data) or {}) do
    if i <= 8 then out[i] = Badges.has(self.game.save, entry) and true or false end
  end
  return out
end

-- a `gen4_trainer_card_art` picture at its anchor plus its own origin
function Gen4TrainerCard:drawSprite(key, x, y)
  local img, rec = self:cardImg(key)
  if not img then return false end
  love.graphics.draw(img, x + (rec.originX or 0), y + (rec.originY or 0))
  return true
end

-- The badge case: MAIN_2 and its button, the badges (priority 2) and their
-- sparkles (1), then -- on the touch screen, `withLid` -- the lid (BG 0) at
-- its current scale and the button's press effect (OBJ 0) over it.
function Gen4TrainerCard:drawBadges(withLid)
  local g = love.graphics
  local panel = self:cardImg("badge_case") or self:img("trainer_card/badge_case")
  g.setColor(1, 1, 1, 1)
  if panel then
    g.draw(panel, 0, 0)
  else
    Font.drawBox(CARD.tx, CARD.ty, CARD.tw, CARD.th)
    Font.draw(Strings("BADGES"), FALLBACK_LABEL_X, 20)
  end
  if self.buttonFace ~= BUTTON_NOT then
    self:drawSprite("case_button_" .. self.buttonFace, 0, 0)
  end

  local earned = self:earned()
  local t = self.t or 0
  for i = 1, 8 do
    if earned[i] then
      local at = BADGE_AT[i]
      local level = Gen4TrainerCard.polishLevel(self:polish(i))
      local key = ("badge_%d_%d"):format(i - 1, Gen4TrainerCard.dirtRow(level))
      g.setColor(1, 1, 1, 1)
      if not (self:drawSprite(key, at[1], at[2]) or self:drawSprite("badge_" .. (i - 1), at[1], at[2])) then
        local badge = self:img(("trainer_card/badge_case_sprites_%02d"):format(i - 1))
        if badge then g.draw(badge, at[1], at[2]) end
      end
    end
  end
  for i = 1, 8 do
    if earned[i] then
      local level = Gen4TrainerCard.polishLevel(self:polish(i))
      local at = SPARKLE_AT[i]
      if level == LEVEL_2_SPARKLES then
        self:drawSprite(("two_sparkles_%d"):format(floor(t / TWO_SPARKLE_TICKS) % SPARKLE_CELLS), at[1], at[2])
      elseif level == LEVEL_4_SPARKLES then
        self:drawSprite(("four_sparkles_%d"):format(floor(t / FOUR_SPARKLE_TICKS) % SPARKLE_CELLS), at[1], at[2])
      end
    end
  end

  if withLid then
    local lid = self:cardImg("badge_case_lid") or self:img("trainer_card/badge_case_lid")
    if lid and self.lidScale > 0 then g.draw(lid, 0, 0, 0, 1, self.lidScale) end
    if self.effectT then
      local frame = floor(self.effectT / EFFECT_TICKS)
      if frame < EFFECT_FRAMES then self:drawSprite("button_effect_" .. frame, EFFECT_X, EFFECT_Y) end
    end
  end
  g.setColor(1, 1, 1, 1)
end

-- Is the touch screen showing?
function Gen4TrainerCard:subscreenShown()
  local okS, SS = pcall(require, "src.ui.SecondScreen")
  if not okS or type(SS) ~= "table" or not SS.mode then return false end
  local mode = SS.mode(self.game)
  return (mode == "display" or mode == "inset") and not SS.stowed(self.game), SS
end

function Gen4TrainerCard:draw()
  local g = love.graphics
  local shown, SS = self:subscreenShown()
  -- the backdrop is sub BG palette entry 0, the case's first colour; the case
  -- picture covers it, so this only shows on a cache without one
  g.setColor(0.10, 0.12, 0.18, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  if self.page == PAGE_CASE and not shown then
    self:drawBadges(false)
  elseif self.page == PAGE_BACK then
    self:drawSide("back")
  else
    self:drawSide("front")
  end
  if shown then
    SS.draw(self.game, function()
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("fill", 0, 0, W, H)
      self:drawBadges(true)
      love.graphics.setColor(1, 1, 1, 1)
    end)
  end
  g.setColor(1, 1, 1, 1)
end

return Gen4TrainerCard
