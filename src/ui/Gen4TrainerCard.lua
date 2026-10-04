-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Platinum's TRAINER CARD, which was falling back to Kanto's.
--
-- Reported from play: "Gen4 bag is missing gen4 pokemon menu is missing gen4
-- options menu is missing and the trainer card as well they are falling back
-- to gen1 art".  This screen now draws Platinum's own card.
--
-- THIS IS THE CARTRIDGE'S CARD, NOT A LIKENESS OF IT.  Three pictures out of
-- `/graphic/trainer_case.narc` and seven row positions out of
-- `src/applications/trainer_case/card_text.c`:
--
--   * `trainer_card/trainer_card_front` and `.../trainer_card_back` -- the
--     two faces, composed from `trainer_card_tiles.NCGR` against the card's
--     own tilemaps.  Drawn at (0, 0); the card sits at y = 8..183 of a
--     256x256 sheet, so the screen's 192 rows hold it with its own margins.
--   * `trainer_card/lucas` or `.../dawn` -- the portrait, by gender.  Its
--     tilemap is full-screen and already positioned: drawn at (0, 0) over the
--     front, the figure lands inside the card's portrait box (x 185..220,
--     y 55..120) without an offset of ours.
--   * THE ROWS come from `sTrainerCardWindowTemplates[]`.  Every window has
--     `tilemapLeft = 2` and `height = 2`, so every label starts at x = 16 and
--     every row is 16 pixels tall.  `TRAINER_CARD_WINDOW_PARTIAL_WIDTH` is 17
--     tiles and `FULL_WIDTH` is 28, so a value's right edge is x = 152 on the
--     short rows and x = 240 on the two long ones.  `tilemapTop` gives the
--     front's rows as 4, 6, 9, 12, 15, 18, 20 -- y = 32, 48, 72, 96, 120,
--     144, 160 -- and the back's as 2, 7, 9, 11.
--
-- Every value is RIGHT-ALIGNED to its window's far edge: `TrainerCard_DrawNumber`
-- and `TrainerCard_DrawString` both print at `windowWidth - (width + endXOffset)`,
-- and the three fields that do not go through them compute the same `xOffset`
-- by hand.  Labels print at 0.  So: label left, value right, on one line.
--
-- THE ENUM PUTS ID BEFORE NAME.  This screen used to print NAME first, which
-- is the Game Boy card's order.  Platinum's is IDNo., NAME, MONEY, POKeDEX,
-- SCORE, TIME, ADVENTURE STARTED.
--
-- TWO CORRECTIONS TO THE FIELDS THEMSELVES, both from `TrainerCase_Init`:
--
--   * POKeDEX IS THE SEEN COUNT, not the owned count -- `Pokedex_CountSeen`.
--     This screen counted owned.
--   * THE ID IS THE LOW HALF, `TrainerInfo_ID_LowHalf`, printed as five
--     digits zero-padded.  Taking it modulo 100000 let a six-digit id show
--     its bottom five rather than its real low half.
--
-- THE TEXT COLOUR is `TEXT_COLOR(1, 2, 0)` on BG palette 15 in every one of
-- the eleven printer calls.  The card is 8bpp, so that is palette entries 241
-- and 242 of the card's own NCLR: (74, 74, 74) for the letter and
-- (164, 164, 164) for its shadow.  Written down rather than read, for the
-- reason [[gen4_screen_palettes]] gives -- the cache publishes the composed
-- picture, which cannot contain a colour that appears only in text.
--
-- WHAT THE PORT CANNOT FILL IN, named rather than faked:
--
--   * SCORE is `GameRecords_GetTrainerScore`, which the port has no record
--     of, so it prints 0 -- the value a new cartridge save prints too.
--   * ADVENTURE STARTED needs a start date the save does not keep, so it
--     prints the cartridge's own blank form, `--- --, ----`.
--   * THE WHOLE BACK FACE is link and Hall-of-Fame records the port does not
--     keep.  It prints the cartridge's blanks and zeroes, which is exactly
--     what Platinum prints before any of it has happened.
--   * THE SIGNATURE panel on the back is part of the art; nothing is written
--     into it.
--
-- THE CARD LEVEL IS NOT THE BADGE COUNT.  An earlier note here guessed it
-- was.  `TrainerCase_CalculateTrainerCardLevel` counts five unrelated
-- things -- game completed, national dex completed, a 100-win Battle Tower
-- streak, contest master in any of five ranks, and an Underground Platinum
-- base flag -- and picks `trainer_card_normal/cobalt/bronze/silver/gold/
-- black` by the total.  Only the first is reachable in the port today.  The
-- six palettes differ ONLY in rows 1-3 and row 15, row 0 being identical in
-- all six, so a level face is one more compose of the same tilemap against a
-- different NCLR -- an EXTRACTOR change, not a screen one, and the cache
-- carries one face today.  Same for `trainer_card_normal_no_dex`; what this
-- screen CAN do without it, and does, is leave the POKeDEX row out entirely
-- before the dex is obtained, as `TrainerCard_DrawFrontText` does.
--
-- WHY A IS A THREE-WAY CYCLE HERE AND A TWO-WAY FLIP ON THE CARTRIDGE.
-- Platinum shows BOTH at once: `GX_SetDispSelect(GX_DISP_SELECT_SUB_MAIN)`
-- puts the sub engine on the top screen, and the card's three layers are all
-- sub while the badge case's two are main -- so the card is the top screen,
-- the badge case is the touch screen, and A flips only the card.  This port
-- shows one screen at a time, so A walks front -> back -> badge case.  The
-- faithful arrangement is for the case to live on the bottom screen behind
-- the screen-toggle button; that is where it belongs once that is wired.
--
-- WHAT IS THE CARTRIDGE'S ON THE BADGE PAGE:
--
--   * THE BADGE CASE SCREEN, `trainer_card/badge_case` -- the "LEAGUE BADGES"
--     panel with its eight empty sockets, composed from its own tilemap.
--   * THE EIGHT BADGES, `trainer_card/badge_case_sprites_00..07`.
--   * WHERE THE BADGES GO.  Measured off the panel rather than guessed: the
--     eight sockets are the only shapes on it darker than its own background,
--     and they come out at x = 43, 99, 155, 211 and y = 59, 115 -- a pitch of
--     56 both ways, four across and two down.  Each badge's art sits in the
--     top-left 40x40 of its 64x64 frame centred on (19.5, 19.5), so a badge
--     drawn twenty pixels up and left of a socket's centre lands in it.
--
-- AND A NOTE ON HOW THE FACE GOT HERE, because both of its faults were ones
-- this file once reported as something else.  The face was scrambled because
-- its tilemap is AFFINE -- one byte per cell, bare tile id -- and the reader
-- took two; that is fixed in `Gen4Graphics.tilemap`.  The portraits were
-- never "composing correctly": they were composing in the badge-case lid's
-- palette, because no NCLR in this archive is named after the card and the
-- planner's fallback found the lid's.  Lucas came out in a tan cap and brown
-- trousers, the right shape in the wrong paint, and an opaque-pixel count
-- said nothing about it.  `palettesFrom` in `Gen4Screens` now names
-- `trainer_card_normal.NCLR` for all four.  Both faults needed LOOKING at
-- the picture; neither showed up in a number.

local Badges = require("src.inventory.Badges")
local Font = require("src.render.Font")
local Gen4Palettes = require("src.render.Gen4Palettes")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")

local Gen4TrainerCard = {}
Gen4TrainerCard.__index = Gen4TrainerCard
Gen4TrainerCard.isOpaque = true

local W, H = 256, 192

-- The badge sockets, measured off `badge_case` itself.
local SOCKET_X = { 43, 99, 155, 211 }
local SOCKET_Y = { 59, 115 }
-- A badge's art is the top-left 40x40 of its 64x64 frame.
local BADGE_OFFSET = 20

-- THE CARD'S OWN SLOTS, out of `sTrainerCardWindowTemplates[]`.  See the head
-- of this file for how each number is arrived at.
local LABEL_X = 16
local PARTIAL_RIGHT = 16 + 17 * 8
local FULL_RIGHT = 16 + 28 * 8
local FRONT_Y = { id = 32, name = 48, money = 72, dex = 96,
                  score = 120, time = 144, started = 160 }
local BACK_Y = { hof = 16, hofTime = 32, linked = 56, battles = 72, trades = 88 }
-- The link-battle row prints four things: W, the wins, L, the losses.  The
-- two letters are placed by tile (14 and 22 tiles in), the two numbers are
-- right-aligned -- the wins with an 8-tile end offset so they stop before L.
local WINS_LABEL_X = 16 + 14 * 8
local WINS_RIGHT = FULL_RIGHT - 8 * 8
local LOSSES_LABEL_X = 16 + 22 * 8

-- TEXT_COLOR(1, 2, 0) on palette 15 of the card's NCLR.  READ FROM THE CACHE
-- now -- `gen4_graphics.palettes` carries every screen's colours and this
-- record's `paletteKey` names the card's -- with these as the fallback for a
-- cache written before that stage existed.
--
-- AND THE FALLBACK WAS WRONG BY ONE.  It said the shadow was (164, 164, 164);
-- the cartridge's is (165, 165, 165).  The 5-bit channel is 20, and 20 of 31
-- is 164.516: the decoder these were read off FLOORED it, while
-- `Gen4Graphics` -- which composed every picture on the screen beside the
-- text -- ROUNDS.  Nothing on screen could show a one-unit difference, which
-- is the whole argument for not writing colours down by hand.
local INK = { { 74 / 255, 74 / 255, 74 / 255 },
              { 165 / 255, 165 / 255, 165 / 255 } }
-- Which bank and which two entries, in the cartridge's own numbering.
local INK_SLOT, INK_LETTER, INK_SHADOW = 15, 1, 2

-- THE MONEY SIGN IS "$", AND IT IS NOT A DOLLAR.  Platinum's own format
-- string is `${STRVAR_1 55, 5, 0}` -- a literal ASCII `$` -- because the DS
-- English font draws that character as the Poke-dollar, a P with a double
-- stroke.  The extracted charmap agrees: code 424 is "$", and glyph 424 on
-- `font_message_sheet.png` is that sign, checked by looking at it.
--
-- IT USED TO BE A LOCAL HERE, with a closing line reading "ShopMenu has the
-- same line and will have the same fault in a Gen 4 shop; that is its own
-- fix".  That fix landed -- `GameVersion.moneySign` is where the three
-- cartridge families' signs live now, and six screens read it -- so the local
-- was the last hand-spelling of a thing with an owner, which is the drift this
-- port keeps finding.  One spelling, and the stale forward reference goes with
-- it.
--
-- (The money WINDOW, pass 179, needs no sign at all: it resolves bank 543
-- entry 19, `"${STRVAR_1 55 0 0}"`, and the cartridge's own format string
-- carries the character.)
local function moneySign()
  return require("src.core.GameVersion").moneySign()
end

-- The cartridge's own blanks, `TrainerCard_Text_BlankDate` and the pair of
-- `TrainerCard_Text_TwoDashes` the time is built from.
local BLANK_DATE = "--- --, ----"
local BLANK_TIME = "--:--"

-- THE SEVEN FACES, by the suffix the graphics stage files each one under.
--
-- `TrainerCase_LoadCardPalette` picks by `TrainerCase_CalculateTrainerCardLevel`
-- when the Pokedex is obtained and by nothing at all when it is not -- the
-- no-dex face wins outright, whatever the level.  The palette is the whole
-- difference: it paints the STAR RATING in the top-right corner, whose tiles
-- sit in the tilemap at every level and are the colour of the card at level 0,
-- and on the no-dex face it hides the POKeDEX row's BAND.  That last one is
-- why this screen skipping the row's TEXT was only half of it.
local LEVEL_SUFFIX = { [0] = "", "_cobalt", "_bronze", "_silver", "_gold",
                       "_black" }
local NO_DEX_SUFFIX = "_no_dex"

-- The pages, in the order A walks them.
local PAGE_FRONT, PAGE_BACK, PAGE_CASE = 1, 2, 3

-- The fallback frame, used only when the cache carries no card art -- an
-- import older than the one that fixed the affine tilemap and the palette.
-- It is this port's own card, and it is meant to look like one.
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
  self.cache = {}
  self.art = ((game.data or {}).gen4_graphics or {}).screens or {}
  if not self.art["trainer_card/badge_case"] then
    Logger.warn("gen4 trainer card: this cache carries no badge case art -- "
                .. "the badge page will be drawn in the engine's own frame")
  end
  -- Which of the seven faces this save gets, and the ink that goes with it --
  -- the black card's letter is (255, 255, 115) on a dark shadow, not the grey
  -- pair every other level uses, and it comes out right because the ink is
  -- read from THIS face's palette rather than from the normal one.
  self.suffix = self:faceSuffix()
  self.inkPair = Gen4Palettes.text(game.data,
                                   "trainer_card/trainer_card_front" .. self.suffix,
                                   INK_SLOT, INK_LETTER, INK_SHADOW)
  if not self.art["trainer_card/trainer_card_front"] then
    Logger.warn("gen4 trainer card: this cache carries no card face -- "
                .. "re-import to get Platinum's own card")
  end
  return self
end

-- WHOSE CARD THIS IS.  `Gen4RowanIntro` writes `save.player.gender`, which is
-- the one place the choice is recorded; anything absent reads as the boy,
-- which is the cartridge's own default before the question is asked.
function Gen4TrainerCard:female()
  local player = (self.game.save or {}).player or {}
  local g = player.gender
  return g == "girl" or g == "female" or g == 1
end

-- One of the cache's screen pictures, by the key the graphics stage files it
-- under.  The record is `{ path, width, height, ... }`; an older cache wrote a
-- bare path, which still resolves.
function Gen4TrainerCard:img(key)
  local rec = self.art[key]
  local path = (type(rec) == "table" and rec.path) or rec
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

-- Two tones, not one: naming both leaves the shadow where the cartridge put
-- it.  A single-colour tint paints letter and shadow alike, which comes out a
-- pixel thicker on two sides and reads as bold.
function Gen4TrainerCard:ink()
  local pair = self.inkPair or INK
  Font.pushStyle({ text = pair[1], shadow = pair[2] })
end

function Gen4TrainerCard:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen4TrainerCard:update()
  local input = self.game.input
  if not input then return end
  if input:wasPressed("a") then
    self.page = self.page % PAGE_CASE + 1
  elseif input:wasPressed("b") or input:wasPressed("start") then
    if self.page ~= PAGE_FRONT then self.page = PAGE_FRONT else self:close() end
  end
end

-- HOW MANY OF THE FIVE THIS SAVE HAS, which is NOT the badge count.
--
-- `TrainerCase_CalculateTrainerCardLevel` adds one for each of: the game
-- completed, the national dex completed, a 100-win streak in any Battle Tower
-- mode, contest master in any of the five ranks, and an Underground Platinum
-- base flag.  The port keeps a record of exactly the first, so that is what is
-- counted; the other four are named here rather than silently scored zero, so
-- the next reader knows the difference between "not implemented" and "not
-- earned".
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

-- Which face, allowing for a cache that predates the variants.
function Gen4TrainerCard:faceSuffix()
  local want = (not self:hasPokedex()) and NO_DEX_SUFFIX
               or (LEVEL_SUFFIX[self:cardLevel()] or "")
  if want ~= "" and not self.art["trainer_card/trainer_card_front" .. want] then
    return ""
  end
  return want
end

-- Has the player been given the Pokedex?  `Flags.hasPokedex` answers it, and
-- since it grew a Gen 4 arm it can say yes on a Sinnoh save -- the two Game
-- Boy event names it tests are not in this port's Gen 4 save, so before that
-- it answered NO for the whole game and this card hid its POKeDEX row and drew
-- the no-dex face forever.  The reasoning lives there rather than here,
-- because the Gen 4 START menu asks the same question through the same
-- function and the two must not drift.
function Gen4TrainerCard:hasPokedex()
  local ok, Flags = pcall(require, "src.script.Flags")
  if not (ok and Flags and Flags.hasPokedex) then return true end
  return Flags.hasPokedex(self.game.save) and true or false
end

-- The front's rows, in the cartridge's own order, each as
-- { label, value, y, right edge }.
function Gen4TrainerCard:frontRows()
  local save = self.game.save or {}
  local player = save.player or {}

  local seen = 0
  for _ in pairs((save.pokedex or {}).seen or {}) do seen = seen + 1 end

  local seconds = 0
  local ok, SaveData = pcall(require, "src.core.SaveData")
  if ok and SaveData and SaveData.playSeconds then
    seconds = math.floor(SaveData.playSeconds(save) or 0)
  end

  local id = math.floor(tonumber(player.id) or 0) % 65536

  local rows = {
    { Strings("IDNo."), ("%05d"):format(id), FRONT_Y.id, PARTIAL_RIGHT },
    { Strings("NAME"), tostring(player.name or Strings("PLAYER")),
      FRONT_Y.name, PARTIAL_RIGHT },
    { Strings("MONEY"), moneySign() .. tostring(math.floor(save.money or 0)),
      FRONT_Y.money, PARTIAL_RIGHT },
  }
  if self:hasPokedex() then
    rows[#rows + 1] = { Strings("POKéDEX"), tostring(seen),
                        FRONT_Y.dex, PARTIAL_RIGHT }
  end
  rows[#rows + 1] = { Strings("SCORE"), "0", FRONT_Y.score, PARTIAL_RIGHT }
  rows[#rows + 1] = {
    Strings("TIME"),
    ("%d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds / 60) % 60),
    FRONT_Y.time, FULL_RIGHT,
  }
  rows[#rows + 1] = { Strings("ADVENTURE STARTED"), BLANK_DATE,
                      FRONT_Y.started, FULL_RIGHT }
  return rows
end

-- The back's rows.  Every value here is a record the port does not keep, so
-- each one is the blank or the zero the cartridge prints before it happens.
function Gen4TrainerCard:backRows()
  return {
    { Strings("HALL OF FAME DEBUT"), BLANK_DATE, BACK_Y.hof, FULL_RIGHT },
    { false, BLANK_TIME, BACK_Y.hofTime, FULL_RIGHT },
    { Strings("TIMES LINKED"), "0", BACK_Y.linked, FULL_RIGHT },
    { Strings("LINK TRADES"), "0", BACK_Y.trades, FULL_RIGHT },
  }
end

-- One row: label at the window's left edge, value ending at its right one.
local function row(label, value, y, right)
  if label then Font.draw(label, LABEL_X, y) end
  if value then Font.draw(value, right - Font.width(value), y) end
end

function Gen4TrainerCard:drawFace()
  local g = love.graphics
  local face = self:img("trainer_card/trainer_card_front" .. self.suffix)
  if not face then return self:drawFallbackFace() end

  g.setColor(1, 1, 1, 1)
  g.draw(face, 0, 0)

  local portrait = self:img(self:female() and "trainer_card/dawn"
                                          or "trainer_card/lucas")
  if portrait then g.draw(portrait, 0, 0) end

  self:ink()
  for _, r in ipairs(self:frontRows()) do row(r[1], r[2], r[3], r[4]) end
  Font.popStyle()
  g.setColor(1, 1, 1, 1)
end

function Gen4TrainerCard:drawBack()
  local g = love.graphics
  local face = self:img("trainer_card/trainer_card_back" .. self.suffix)
  if not face then return self:drawFallbackFace() end

  g.setColor(1, 1, 1, 1)
  g.draw(face, 0, 0)

  self:ink()
  for _, r in ipairs(self:backRows()) do row(r[1], r[2], r[3], r[4]) end
  -- The link-battle row is the one that does not fit the label/value shape.
  Font.draw(Strings("LINK BATTLES"), LABEL_X, BACK_Y.battles)
  Font.draw(Strings("W"), WINS_LABEL_X, BACK_Y.battles)
  Font.draw("0", WINS_RIGHT - Font.width("0"), BACK_Y.battles)
  Font.draw(Strings("L"), LOSSES_LABEL_X, BACK_Y.battles)
  Font.draw("0", FULL_RIGHT - Font.width("0"), BACK_Y.battles)
  Font.popStyle()
  g.setColor(1, 1, 1, 1)
end

-- This port's own card, drawn only when the cache has no face to draw.
function Gen4TrainerCard:drawFallbackFace()
  Font.drawBox(CARD.tx, CARD.ty, CARD.tw, CARD.th)
  local title = Strings("TRAINER CARD")
  Font.draw(title, math.floor((W - Font.width(title)) / 2), 14)

  local y = FALLBACK_FIRST_ROW
  for _, r in ipairs(self:frontRows()) do
    if r[1] then Font.draw(r[1], FALLBACK_LABEL_X, y) end
    Font.draw(r[2], FALLBACK_VALUE_X, y)
    y = y + FALLBACK_ROW_PITCH
  end
end

-- How many badges this save has, and which.  `Badges.list` is the dataset's
-- own order, so a hack that renames or reorders them still lines up.
function Gen4TrainerCard:earned()
  local out = {}
  for i, entry in ipairs(Badges.list(self.game.data) or {}) do
    if i <= 8 then out[i] = Badges.has(self.game.save, entry) and true or false end
  end
  return out
end

function Gen4TrainerCard:drawBadges()
  local g = love.graphics
  local panel = self:img("trainer_card/badge_case")
  if panel then
    g.setColor(1, 1, 1, 1)
    g.draw(panel, 0, 0)
  else
    Font.drawBox(CARD.tx, CARD.ty, CARD.tw, CARD.th)
    Font.draw(Strings("BADGES"), FALLBACK_LABEL_X, 20)
  end

  local earned = self:earned()
  for i = 1, 8 do
    if earned[i] then
      local badge = self:img(("trainer_card/badge_case_sprites_%02d"):format(i - 1))
      if badge then
        local x = SOCKET_X[(i - 1) % 4 + 1]
        local y = SOCKET_Y[math.floor((i - 1) / 4) + 1]
        g.setColor(1, 1, 1, 1)
        g.draw(badge, x - BADGE_OFFSET, y - BADGE_OFFSET)
      end
    end
  end
end

function Gen4TrainerCard:draw()
  local g = love.graphics
  g.setColor(0.10, 0.12, 0.18, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  if self.page == PAGE_CASE then
    self:drawBadges()
  elseif self.page == PAGE_BACK then
    self:drawBack()
  else
    self:drawFace()
  end
  g.setColor(1, 1, 1, 1)
end

return Gen4TrainerCard
