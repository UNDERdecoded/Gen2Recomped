-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Emerald's summary screen.
--
-- Gen 2's is three pages behind a persistent header.  Emerald's is FOUR, and
-- the difference is not one more page -- it is that two of the four exist to
-- show things Johto does not have:
--
--   INFO           dex number, species, types, OT, ID, and the trainer memo,
--                  whose first line is the NATURE -- a Gen 3 concept
--   SKILLS         the six stats, and the six are SPLIT: Sp. Atk and Sp. Def
--                  are separate numbers, where Gen 2 has one Special.  The
--                  nature raises one and lowers another, and the cartridge
--                  says which by colouring them.
--   BATTLE MOVES   four moves with type, PP, power and accuracy
--   CONTEST MOVES  the same four moves in the other language the game speaks
--                  about them
--
-- WHAT COMES OFF THE CARTRIDGE: the page names, the stat names, the nature
-- table and which stat each nature raises and lowers, the split base stats,
-- the type names, the dex numbers, and the move data.  All of it is read by
-- the extractor and none of it is written here.
--
-- WHAT IS RECONSTRUCTED: the LAYOUT -- which box sits where, how wide it is,
-- which column a value starts in.  Emerald draws this screen from background
-- art this port has not located, so the panels here are the cartridge's own
-- window frame drawn at reconstructed geometry.  Those numbers are together
-- at the top of the file and they are the part to correct against a
-- screenshot.

local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Stats = require("src.pokemon.Stats")
local Strings = require("src.core.Strings")
local TypeChart = require("src.battle.TypeChart")

local Gen3SummaryMenu = {}
Gen3SummaryMenu.__index = Gen3SummaryMenu
Gen3SummaryMenu.isOpaque = true
Gen3SummaryMenu.holdsUIAnchors = true

local GBA_W, GBA_H = 240, 160

function Gen3SummaryMenu:uiSize() return GBA_W, GBA_H end

-- THE GEOMETRY IS THE CARTRIDGE'S ART, MEASURED.
--
-- Every number below was read off the background this screen now draws --
-- extractSummaryScreen renders Emerald's own five page tilemaps -- rather
-- than chosen to look about right.  The right-hand column's panels start at
-- x=84 and end at x=238 on all four pages; the headings sit on the coloured
-- bar above each panel; the left eighty pixels are the Pokemon's own panel,
-- which is a separate background layer on the cartridge and is cut out of the
-- info page here.
--
-- The old drawn boxes are kept for a cache imported before the art existed:
-- with no picture the screen paints its panels exactly as it did.
local HEADER = { tx = 0, ty = 0, tw = 30, th = 5 }
local PAGE   = { tx = 0, ty = 5, tw = 30, th = 15 }
local PIC_X, PIC_Y = 8, 8
local ROW_PITCH = 14

-- the Pokemon's own panel down the left, measured off the art: a 64x64
-- picture box with a band above it for the name and one below for the level
local PANEL_TEXT_X = 8
-- and the two columns inside the level band, both window-relative
-- (08:$1C271E `mov r2,#24`, 08:$1C2808 `mov r2,#57`)
local PANEL_LEVEL_X = 24
local PANEL_GENDER_X = 57

-- the gap between "TYPE/" and the icons the cartridge draws after it; the
-- port prints names there instead, so this is the only chosen number on the
-- row and it is a space, not a layout
local TYPE_GAP = 4
local PANEL_NAME_Y = 18
local PANEL_PIC_X, PANEL_PIC_Y, PANEL_PIC_W = 8, 32, 64
local PANEL_LEVEL_Y = 100
local PANEL_HP_Y = 114

-- the right-hand column, in pixels off the art
local COL_X = 84          -- where every panel starts
local COL_RIGHT = 238     -- ...and ends
local TEXT_X = COL_X + 4  -- the inset the cartridge prints values at
local HEAD_X = COL_X + 12 -- ...and the one it prints a heading at

-- INFO: three headed blocks, each a bar with one or two rows under it
local INFO_ROWS = {
  { head = 24, rows = { 35, 50 } },
  { head = 65, rows = { 75, 90 } },
  { head = 105, rows = { 115, 130, 145 } },
}
-- SKILLS: the ITEM/RIBBON pair, the STATS grid, and the EXP block
local SKILL_HEAD = { 24, 48, 104 }
local SKILL_ITEM_Y = 35
local SKILL_STAT_Y = 60
local SKILL_STAT_PITCH = 14
local SKILL_STAT_VALUE_X = 128   -- the grid's first value column ends here
local SKILL_STAT_RIGHT_X = 176   -- ...and the second pair starts here
local SKILL_STAT_RIGHT_VALUE = 232
local SKILL_EXP_Y = 116
-- MOVES: the list, then the effect/description block
local MOVE_HEAD_Y = 24
local MOVE_ROW_Y = 40
local MOVE_ROW_PITCH = 13
-- ...and the moves page's right-hand column.  The cartridge right-aligns
-- the PP inside its own window, which starts at 192 and is 48 wide; this
-- constant is the fallback for a cache with no window table.
local MOVE_PP_X = 190
local MOVE_DESC_HEAD_Y = 98
local MOVE_DESC_Y = 122

-- kept so the pre-art fallback still has somewhere to print
local LABEL_X = 24
local VALUE_X = 120
local RIGHT_LABEL_X = 132
local RIGHT_VALUE_X = 208

-- the nature's mark on a stat, which is the thing the Game Boy screen has no
-- way to say
local RAISED = { 1.0, 0.45, 0.35 }
local LOWERED = { 0.45, 0.65, 1.0 }
-- the gender marks are printed in colours 3 and 4, which are the cartridge's
-- own blue and red (08:$1C280C / $1C2828)
local MALE = { 0.30, 0.45, 0.95 }
local FEMALE = { 0.95, 0.35, 0.45 }
local PLAIN = { 0, 0, 0 }

-- ---------------------------------------------------------------------------
-- the page names, which are the cartridge's when it has them
-- ---------------------------------------------------------------------------

local FALLBACK_PAGES = {
  "POKéMON INFO", "POKéMON SKILLS", "BATTLE MOVES", "CONTEST MOVES",
}

local warned = false
local function warnOnce(fmt, ...)
  if warned then return end
  warned = true
  Logger.warn("gen3 summary: " .. fmt, ...)
end

-- THE WORDS ARE THE CARTRIDGE'S NOW.
--
-- Every label on these four pages used to be English typed into this file,
-- and "its own English" is exactly how a screen ends up ALMOST right:
-- "EXP" where the cartridge says "EXP. POINTS", "CONTEST MOVES" where the
-- cartridge -- famously -- says "C0NTEST MOVES", with a ZERO.  The whole
-- block is one run in the ROM and extractSummaryText reads it; what is below
-- is what a cache imported before that existed still shows.
local function summaryText(game)
  local constants = (game and game.data and game.data.constants) or {}
  local record = constants.gen3Summary
  return type(record) == "table" and record or nil
end

Gen3SummaryMenu.summaryText = summaryText

-- ---------------------------------------------------------------------------
-- THE PAGE'S OWN BACKGROUND
--
-- Five tilemaps come off the cartridge: the four pages, plus the info page's
-- variant for a Pokemon with no dex entry.  The Pokemon's panel down the left
-- is a separate background layer on hardware -- present on every page -- and
-- only the info map carries it, so the extractor cuts it out as `panel` and
-- it is drawn under whichever page is up.
-- ---------------------------------------------------------------------------

local ART_BY_PAGE = { "info", "skills", "battle_moves", "contest_moves" }
-- ...and which of those four the move list is on, which is where a Pokemon
-- learning a fifth move is asked its question
local MOVES_PAGE = 3
-- the cursor the font stage draws for Hoenn, the same code the move-learn
-- screen's own list used before this one took the question over
local CHOOSE_CURSOR = 0x2F
-- ...and its hollow twin, which marks the move being HELD while a swap is
-- half-made: the solid one is where you are, the hollow one is what you
-- picked up.  Emerald says the same thing by tinting the held row.
local HELD_CURSOR = 0x30

local function artFor(game, key)
  local record = summaryText(game)
  local art = record and record.pageArt
  local path = art and art[key]
  if not path then return nil end
  local ok, image = pcall(require("src.render.Assets").image, path)
  return ok and image or nil
end

Gen3SummaryMenu.artFor = artFor

-- one label, the cartridge's if it has it
local function word(game, key, fallback)
  local record = summaryText(game)
  local value = record and record[key]
  if type(value) == "string" and #value > 0 then return value end
  return Strings(fallback)
end

local function pageNames(game)
  local record = summaryText(game)
  if record and type(record.pages) == "table" and record.pages[1] then
    return record.pages
  end
  local screens = (game.data.constants or {}).gen3Screens
  local named = screens and screens.summaryPages
  if type(named) == "table" and named[1] then return named end
  return FALLBACK_PAGES
end

-- ---------------------------------------------------------------------------

function Gen3SummaryMenu.new(game, opts)
  local self = setmetatable({}, Gen3SummaryMenu)
  self.game = game
  opts = opts or {}
  self.mon = opts.mon
  self.onCancel = opts.onCancel
  self.page = 1
  self.pages = pageNames(game)
  -- PICKING A MOVE TO FORGET.
  --
  -- Emerald does not put up a list of its own when a Pokemon has four moves
  -- and is learning a fifth: it opens THIS screen on the moves page with a
  -- cursor, and the fifth move sits under the four as the thing you pick if
  -- you would rather not learn it.  `choose` is what turns that on -- without
  -- it this screen behaves exactly as it always has.
  self.choose = opts.choose
  if type(self.choose) == "table" then
    self.page = math.min(MOVES_PAGE, #self.pages)
    self.moveIndex = 1
  end
  self.def = self.mon and game.data.pokemon
             and game.data.pokemon[self.mon.species] or nil
  if not self.def then
    warnOnce("no species record for %s", tostring(self.mon and self.mon.species))
  end
  self.pic = nil
  if self.mon then
    local ok, path = pcall(function()
      return (require("src.pokemon.Sprites").path(game.data, self.mon.species,
                                                  "front", { mon = self.mon }))
    end)
    if ok and path then
      local okImg, img = pcall(love.graphics.newImage, path)
      if okImg then self.pic = img end
    end
    -- THE PIC MOVES ON THIS SCREEN.  Emerald plays the front-pic animation
    -- when the summary opens, the same way it plays it when a Pokemon is sent
    -- out, and this port drives both through the same module -- so the record
    -- the sprite stage now writes is all this needed.
    local okAnim, anim = pcall(function()
      -- forMon, not new: a shiny animates from its own strip
      return require("src.pokemon.PicAnim").forMon(game.data, self.mon)
    end)
    self.picAnim = okAnim and anim or nil
    if self.picAnim then self.picAnim:start() end
    -- ...and the OTHER half of it.  A Gen 3 front pic does two things at
    -- once: it swaps between two pictures (above) and the sprite itself
    -- squashes, hops or glows -- one routine per species out of the
    -- cartridge's own table.  The battle screen plays both; this page plays
    -- the same two, because Emerald plays them here too.
    local okMon, mon = pcall(function()
      return require("src.pokemon.MonAnim").new(game.data, self.mon.species)
    end)
    self.monAnim = okMon and mon or nil
    if self.monAnim then self.monAnim:start() end
  end
  return self
end

-- The pic, through whatever the species' own routine is doing to it this
-- frame.  Same transform the battle screen applies, about the same point --
-- the pic's bottom centre, which is what it is standing on.
function Gen3SummaryMenu:drawMon(image, x, y)
  if not image then return end
  local BattleState = require("src.battle.BattleState")
  if self.monAnim and BattleState.drawMonAnimated then
    BattleState.drawMonAnimated({ monAnim = self.monAnim }, image, x, y, 1)
    return
  end
  love.graphics.draw(image, x, y)
end

function Gen3SummaryMenu:close()
  if self.game.stack then self.game.stack:pop() end
  if self.onCancel then self.onCancel() end
end

-- THE CHOOSER'S OWN INPUT.  While a move is being picked the pages are
-- locked -- the cartridge does not let you walk off the moves page in the
-- middle of the question -- and up/down run over the four moves plus the
-- fifth the Pokemon is being taught.
function Gen3SummaryMenu:chooseInput(input)
  local rows = self:chooseRows()
  local index = math.max(1, math.min(rows, math.floor(self.moveIndex or 1)))
  if input:wasPressed("up") then
    index = index > 1 and index - 1 or rows
  elseif input:wasPressed("down") then
    index = index < rows and index + 1 or 1
  elseif input:wasPressed("a") then
    self.moveIndex = index
    self:answer(index)
    return
  elseif input:wasPressed("b") then
    self.moveIndex = index
    self:answer(nil)
    return
  end
  self.moveIndex = index
end

-- the four the Pokemon knows, and the one it is being offered
function Gen3SummaryMenu:chooseRows()
  local moves = (self.mon and self.mon.moves) or {}
  return math.min(4, #moves) + 1
end

function Gen3SummaryMenu:answer(index)
  local choose = self.choose
  self.choose = nil
  if self.game.stack then self.game.stack:pop() end
  if choose and choose.onChoose then choose.onChoose(index) end
end

-- ---------------------------------------------------------------------------
-- MOVE SELECTION
--
-- Reported from play: "Battle moves page of the stats/summary menu in emerald
-- i cant scroll through the moves".  There was nothing to scroll with: outside
-- the learn-a-fifth-move flow this screen had no cursor at all, A closed it,
-- and the EFFECT and DESCRIPTION boxes were hard-wired to the FIRST move -- so
-- the bottom half of the page could only ever describe one of the four.
--
-- Emerald's own Task_HandleInput (08:$1C174C) is where the model comes from,
-- and A does not mean the same thing on every page:
--
--   UP / DOWN        change which PARTY POKEMON is shown
--   LEFT / RIGHT     change page (L and R do the same)
--   A                on INFO or SKILLS, closes; on either MOVES page it
--                    enters MOVE SELECTION (08:$1C1826, whose decision
--                    routine at $1C18A8 is what picks between the two)
--   B                closes
--
-- ...and inside move selection (08:$1C1940) UP and DOWN walk the cursor over
-- the moves, A picks one to swap and A again puts it in the second slot, B
-- backs out.  Swapping the SLOT rather than the move id is what carries each
-- move's own PP with it.
function Gen3SummaryMenu:movesPage()
  return self.page == MOVES_PAGE
    or (self.page == MOVES_PAGE + 1 and #self.pages > MOVES_PAGE)
end

-- how many rows the cursor may stand on: the moves the Pokemon actually
-- knows, never the four empty slots a fresh Pokemon shows as "-"
function Gen3SummaryMenu:knownMoves()
  local moves = (self.mon and self.mon.moves) or {}
  local n = 0
  for i = 1, math.min(4, #moves) do
    local slot = moves[i]
    local id = (type(slot) == "table") and slot.id or slot
    if id then n = i end
  end
  return n
end

-- Which move the EFFECT and DESCRIPTION boxes are about.  With no cursor up
-- that is the first one, which is what the cartridge shows when the page
-- opens; with one it is whatever the cursor is standing on.
function Gen3SummaryMenu:selectedMove()
  local rows = self:knownMoves()
  if rows < 1 then return 1 end
  if not (self.moveSelect or type(self.choose) == "table") then return 1 end
  return math.max(1, math.min(rows, math.floor(self.moveIndex or 1)))
end

function Gen3SummaryMenu:enterMoveSelect()
  if self:knownMoves() < 1 then return false end
  self.moveSelect = true
  self.moveIndex = math.max(1, math.min(self:knownMoves(),
                                        math.floor(self.moveIndex or 1)))
  self.moveSwapFrom = nil
  return true
end

function Gen3SummaryMenu:leaveMoveSelect()
  self.moveSelect = nil
  self.moveSwapFrom = nil
end

-- A on a second row: put the two slots where the other one was.  The whole
-- slot travels, so a move keeps the PP it had rather than inheriting the
-- other's.
function Gen3SummaryMenu:swapMoves(a, b)
  local moves = self.mon and self.mon.moves
  if not (moves and a and b and a ~= b) then return end
  moves[a], moves[b] = moves[b], moves[a]
end

function Gen3SummaryMenu:moveSelectInput(input)
  local rows = self:knownMoves()
  if rows < 1 then
    self:leaveMoveSelect()
    return
  end
  -- LEFT AND RIGHT ARE NOT INERT IN HERE, and they are not the page keys
  -- either: the ROM's move-select handler (08:$1C19DC, $1C1A66) lets you cross
  -- between the TWO MOVES PAGES only -- LEFT does nothing on BATTLE MOVES
  -- because there is no moves page to its left -- and crossing puts the task
  -- back to Task_HandleInput, so the list closes on the way.
  if input:wasPressed("left") and self.page == MOVES_PAGE + 1 then
    self.page = MOVES_PAGE
    self:leaveMoveSelect()
    return
  elseif input:wasPressed("right") and self.page == MOVES_PAGE
         and #self.pages > MOVES_PAGE then
    -- guarded on the page COUNT: a dataset whose page names came up short
    -- has no contest page to cross to, and stepping onto one that is not
    -- there would draw a page this screen cannot name
    self.page = MOVES_PAGE + 1
    self:leaveMoveSelect()
    return
  end
  local index = math.max(1, math.min(rows, math.floor(self.moveIndex or 1)))
  if input:wasPressed("up") then
    index = index > 1 and index - 1 or rows
  elseif input:wasPressed("down") then
    index = index < rows and index + 1 or 1
  elseif input:wasPressed("a") then
    if self.moveSwapFrom then
      self:swapMoves(self.moveSwapFrom, index)
      self.moveSwapFrom = nil
    else
      self.moveSwapFrom = index
    end
  elseif input:wasPressed("b") then
    -- B backs out of a half-finished swap first, and only then out of the
    -- mode: pressing it once should not undo the choice AND leave.
    if self.moveSwapFrom then
      self.moveSwapFrom = nil
    else
      self:leaveMoveSelect()
    end
    return
  end
  self.moveIndex = index
end

function Gen3SummaryMenu:update(dt)
  if self.picAnim then self.picAnim:update(dt) end
  if self.monAnim then self.monAnim:update(dt) end
  local input = self.game.input
  if not input then return end
  if type(self.choose) == "table" then
    self:chooseInput(input)
    return
  end
  if self.moveSelect then
    self:moveSelectInput(input)
    return
  end
  local n = #self.pages
  if input:wasPressed("right") then
    self.page = self.page % n + 1
    self:leaveMoveSelect()
  elseif input:wasPressed("left") then
    self.page = (self.page - 2) % n + 1
    self:leaveMoveSelect()
  elseif input:wasPressed("a") then
    -- the cartridge's split: the moves pages open their list, the other two
    -- close the screen
    if not (self:movesPage() and self:enterMoveSelect()) then self:close() end
  elseif input:wasPressed("b") then
    self:close()
  end
end

-- ---------------------------------------------------------------------------
-- what the nature does to a stat, read off the extracted nature table
--
-- A nature record carries `raises` and `lowers` as stat KEYS -- attack,
-- defense, speed, spatk, spdef -- and the five neutral ones carry neither.
-- HP is never touched, which is why it has no colour on this screen.
-- ---------------------------------------------------------------------------

function Gen3SummaryMenu:natureRecord()
  local mon = self.mon
  local name = mon and mon.nature
  if not name then return nil end
  local record = Stats.natureFor(name)
  if record then return record end
  local natures = (self.game.data.constants or {}).natures
  return natures and natures[name] or nil
end

function Gen3SummaryMenu:statColour(key)
  local record = self:natureRecord()
  if not record then return PLAIN end
  if record.raises == key then return RAISED end
  if record.lowers == key then return LOWERED end
  return PLAIN
end

-- ---------------------------------------------------------------------------

local function put(text, x, y, colour)
  love.graphics.setColor(colour[1], colour[2], colour[3], 1)
  Font.draw(tostring(text or ""), x, y)
end

-- ---------------------------------------------------------------------------
-- EVERY STRING ON THIS SCREEN IS PRINTED INTO A WINDOW, and this port was
-- printing them onto the screen.  Three things follow from that difference,
-- and all three were visible:
--
--   1. A WINDOW CLIPS.  The hardware draws into the window's own bitmap, so a
--      string wider than its box is cut off at the edge.  Nothing here cut
--      anything, so a long move name ran out of its panel and over the PP
--      column beside it.  The widest move name in the cartridge's own font is
--      72 pixels and the move-name window is 72 wide -- the fit is EXACT, by
--      design, which is why any drift at all shows.
--
--   2. x AND y ARE RELATIVE TO THE WINDOW.  `x=53` in the ROM means 53 pixels
--      into the POWER/ACCURACY box, not 53 pixels into the screen.
--
--   3. THE SCREEN USES THREE ALIGNMENTS, not one.  Emerald calls
--      GetStringCenterAlignXOffset (08:$1DB35C) and GetStringRightAlignXOffset
--      (08:$1DB368) as often as it passes a plain x, and this port left-aligned
--      everything -- so HP sat where the H of a seven-letter DEFENSE would go,
--      and every number that should have ended at a column's right edge began
--      there instead.
--
-- So a print is (window, x-spec, window-relative y, colour), where an x-spec
-- is a number, `{ center = width, plus = d }` or `{ right = width, plus = d }`
-- -- the same three shapes the cartridge's call sites take.
-- ---------------------------------------------------------------------------

local function windowX(win, text, spec)
  local base = win and win.x or 0
  if type(spec) == "number" then return base + spec end
  if type(spec) ~= "table" then return base end
  local width = Font.width(tostring(text or ""))
  local plus = spec.plus or 0
  if spec.center then
    -- the ROM's own rounding: an integer divide, so a string one pixel wider
    -- than its half lands left rather than right
    return base + plus + math.floor(math.max(0, spec.center - width) / 2)
  end
  if spec.right then
    return base + plus + math.max(0, spec.right - width)
  end
  return base + plus
end

-- Draw inside `win`, clipped to it.  A nil window means the caller had no
-- cartridge table to place from (an old cache), and then this is a plain put
-- at whatever the fallback geometry said -- unclipped, exactly as before.
local function putIn(win, text, spec, y, colour)
  if not win then
    put(text, type(spec) == "number" and spec or 0, y, colour or PLAIN)
    return
  end
  local x = windowX(win, text, spec)
  local scissor = love.graphics.setScissor
  local ox, oy, ow, oh
  if scissor then
    ox, oy, ow, oh = love.graphics.getScissor()
    scissor(win.x, win.y, win.width, win.height)
  end
  put(text, x, win.y + (y or 0), colour or PLAIN)
  if scissor then
    if ox then scissor(ox, oy, ow, oh) else scissor() end
  end
end

Gen3SummaryMenu.windowX = windowX

-- ---------------------------------------------------------------------------
-- WHERE A ROW GOES
--
-- With the cartridge's art up, the rows are not evenly spaced: each page is
-- blocks of panels with a coloured heading bar between them, and a row has to
-- land INSIDE a panel or it prints over a bar.  These are measured off the
-- rendered background, block by block, and they are why this screen no longer
-- needs a pitch at all.
--
-- Without the art -- a cache imported before extractSummaryScreen existed --
-- the old even pitch is handed back and the page draws exactly as it did.
-- Script_PrintMoveNameAndPP's own step: `lsl r0,r7,#4` -- the move index
-- shifted left four, which is sixteen.
local MOVE_ROW_PITCH = 16
local MOVE_SLOTS = 5

-- The PP string is right-aligned to this many pixels inside the PP window
-- (PrintMoveNameAndPP: `mov r2,#44 / bl GetStringRightAlignXOffset`).  The
-- window is 48 wide, so the four pixels left over are the gap at its right
-- edge.
local MOVE_PP_RIGHT = 44

-- POWER and ACCURACY print their numbers 53 pixels into their own window
-- (08:$1C3CB8, `mov r2,#53`), which is a column, not a gap after the label.
local POWER_VALUE_X = 53

-- and the ID number is right-aligned to 56 inside its own window
-- (08:$1C2F96, `mov r2,#56`)
local INFO_ID_RIGHT = 56

-- "PP" IS ONE GLYPH ON THE CARTRIDGE.  The template at $861CE97 is
-- `{SYMBOL 6}{VAR1}/{VAR2}` -- the extra-symbol escape, whose sixth entry is
-- the PP ligature -- so there is no space between the label and the number and
-- the whole thing is one right-aligned string.  This charmap has PK and MN as
-- ligatures but not PP, so the two letters stand in for it; what matters for
-- the layout is that it travels WITH the numbers instead of being printed at
-- the window's left edge, which is what pushed the pair out of the box.
local function ppSymbol()
  return "PP"
end

local ART_ROWS = {
  info   = { 35, 50, 75, 90, 115, 130, 145 },
  skills = { 35, 60, 74, 88, 116, 130, 144 },
  moves  = { 40, 53, 66, 79, 122, 136, 150 },
}

-- published so the layout can be checked as arithmetic: seven rows, and the
-- memo's three have to land ON a 160-pixel screen
Gen3SummaryMenu.ART_ROWS = ART_ROWS

-- ...AND THE CARTRIDGE'S OWN, WHEN THE IMPORT HAS READ THEM.
--
-- Every row above was measured off the rendered background by eye, and that
-- is exactly as accurate as it sounds: the skills rows came out on a
-- fourteen-pixel pitch where the cartridge's is SIXTEEN, and the moves on
-- thirteen where it is also sixteen -- so the fourth line of each drifted
-- three and nine pixels out of its own box.
--
-- Emerald prints each of these inside a WindowTemplate, and the templates
-- are a table: sSummaryTemplate for the labels and the left column, then
-- three fixed-length arrays for the pages.  extractSummaryWindows reads all
-- four.  What comes back is the window's corner, and the row pitch is the
-- window's own height divided by how many rows it holds.
function Gen3SummaryMenu:windows()
  return (self.game.data.constants or {}).gen3SummaryWindows
end

local function rowsFrom(win, count, first)
  local out = {}
  local pitch = math.floor(win.height / count)
  for i = 1, count do out[i] = win.y + (first or 1) + (i - 1) * pitch end
  return out
end

function Gen3SummaryMenu:rows()
  if not self.hasArt then
    local out, y = {}, (PAGE.ty + 1) * 8
    for i = 1, 8 do out[i] = y + (i - 1) * ROW_PITCH end
    return out
  end
  local w = self:windows()
  if w then
    if self.page == 2 then
      -- ITEM/RIBBON, then the three stat rows of the left column, then the
      -- two EXP rows -- seven, which is what the callers expect
      local stats = rowsFrom(w.labels[11], 3)
      return { w.skills[1].y + 1, stats[1], stats[2], stats[3],
               w.skills[5].y + 1, w.skills[5].y + 17, w.skills[5].y + 33 }
    elseif self.page == 1 then
      return { w.info[1].y + 1, w.info[2].y + 1,
               w.info[3].y + 1, w.info[3].y + 17,
               w.info[4].y + 1, w.info[4].y + 17, w.info[4].y + 33 }
    else
      -- FIVE SLOTS OF SIXTEEN, not four of twenty.  PrintMoveNameAndPP
      -- (08:$1C3B08) prints move i at `y = i * 16 + 1` and the fifth row --
      -- the move being offered, or CANCEL -- at y = 65, which is 4*16+1.  The
      -- window is 80 tall because it holds FIVE rows; dividing its height by
      -- the four a Pokemon can know gave a 20-pixel pitch and walked rows two,
      -- three and four four, eight and twelve pixels below their own lines in
      -- the background art.
      local m = {}
      for i = 1, 5 do m[i] = w.moves[1].y + 1 + (i - 1) * MOVE_ROW_PITCH end
      return { m[1], m[2], m[3], m[4],
               w.moves[3].y + 1, w.moves[3].y + 17, w.moves[3].y + 33, m[5] }
    end
  end
  local key = (self.page == 1 and "info")
    or (self.page == 2 and "skills") or "moves"
  return ART_ROWS[key]
end

-- ...and which column.  The panels run from x=84 to x=238 on every page, so
-- the four columns below are the same on all of them.
function Gen3SummaryMenu:cols()
  if not self.hasArt then
    return LABEL_X, VALUE_X, RIGHT_LABEL_X, RIGHT_VALUE_X
  end
  local w = self:windows()
  if w then
    -- EACH PAGE HAS ITS OWN COLUMNS.  They are not one grid the three pages
    -- share -- that is the assumption that put the move names 32 pixels left
    -- of where the cartridge draws them.
    if self.page == 3 or self.page == 4 then
      -- the move list and the PP column beside it, each its own window
      return w.moves[1].x, w.moves[2].x + 44,
             w.moves[1].x, w.moves[2].x + 44
    end
    if self.page == 1 then
      -- OT and the ID number, then the ability block under them
      return w.info[1].x, w.info[2].x, w.info[3].x, w.info[3].x
    end
    -- the two stat label windows and the two value windows, which are four
    -- separate rectangles: the right value column starts at 216, and this
    -- port had it at 192
    return w.labels[11].x + 6, w.skills[3].x + 4,
           w.labels[12].x + 2, w.skills[4].x + 2
  end
  return TEXT_X, SKILL_STAT_RIGHT_X - 48, SKILL_STAT_RIGHT_X,
         SKILL_STAT_RIGHT_VALUE - 40
end

-- The left column's three lines: the nickname, then "/SPECIES" with the
-- level and the gender under it, then the dex number up at the top.  All
-- three are their own windows -- 18, 19 and 17 -- and the port had the
-- nickname 79 pixels away from where the cartridge puts it.
function Gen3SummaryMenu:panelRows()
  local w = self:windows()
  if not w then
    return PANEL_NAME_Y, PANEL_LEVEL_Y, PANEL_HP_Y
  end
  return w.labels[19].y + 1, w.labels[20].y + 17, w.labels[18].y + 1
end

-- WHICH PAGES SHOW THE LEVEL BAND.
--
-- Window 19 -- the species, the level and the gender -- is at (8,112) and is
-- 32 tall, so it covers rows 112 to 143.  The two moves pages put their EFFECT
-- box in that same corner: window 14 (POWER/ACCURACY) and window 15
-- (APPEAL/JAM) are both at (8,120).  Two windows cannot occupy one rectangle,
-- so the cartridge hides window 19 on those pages -- and the port, which drew
-- it regardless, printed "Lv30" straight across POWER and ACCURACY, and across
-- APPEAL and JAM on top of the contest hearts.
function Gen3SummaryMenu:showsLevelBand()
  return self.page ~= 3 and self.page ~= 4
end

-- The gender mark, or nil.  NIDORAN's two forms are the cartridge's own
-- exception (08:$1C27E4: species 29 and 32 print nothing), because their
-- NAMES already carry the symbol and printing a second one reads as a typo.
local NIDORAN_DEX = { [29] = true, [32] = true }
function Gen3SummaryMenu:genderMark()
  local mon, def = self.mon, self.def
  if not mon then return nil end
  if def and NIDORAN_DEX[tonumber(def.dex) or -1] then return nil end
  -- the port's own answer, which falls back to the species' gender ratio when
  -- the save has not stamped one -- a mon with no `gender` field is not
  -- genderless, it is one nothing has asked about yet
  local ok, Pokemon = pcall(require, "src.pokemon.Pokemon")
  if not (ok and Pokemon and Pokemon.genderOf) then return nil end
  local g = Pokemon.genderOf(self.game.data, mon)
  if g == "male" then return "\u{2642}" end
  if g == "female" then return "\u{2640}" end
  return nil
end

-- ---------------------------------------------------------------------------
-- THE FOUR PAGE DOTS
--
-- Reported from play: "in the top middle theres a graphic with 4 dots that
-- doesnt appear on the other pages and move the dot for each page".
--
-- They are not part of any page's art.  DrawPagination (08:$1C1BA0) builds an
-- 8x2 block of tile entries every time the page changes and copies it to tile
-- (11,0) -- so a static tilemap has no reason to carry it.  The INFO page's
-- happens to have been compressed with a page-1 row still in it, which is
-- exactly why the dots showed on that one page and nowhere else, and why they
-- never moved.
--
-- Each page is two tiles wide and two tall, and the six pairs the routine
-- picks between are not simply filled and empty: the run is drawn as a pill,
-- so the last cell carries its right-hand cap and a dot's art depends on where
-- it sits as well as on whether it is the current one.
function Gen3SummaryMenu:pagination()
  local record = summaryText(self.game)
  local pages = record and record.pagination
  if not (pages and pages.image) then return nil end
  if self._pageStrip == nil then
    local ok, image = pcall(require("src.render.Assets").image, pages.image)
    self._pageStrip = (ok and image) or false
  end
  if not self._pageStrip then return nil end
  return pages, self._pageStrip
end

function Gen3SummaryMenu:drawPagination()
  local pages, image = self:pagination()
  if not pages then return end
  local count = math.min(pages.pages or 4, #(self.pages or {}))
  if count < 1 then return end
  local current = math.max(1, math.min(count, self.page or 1)) - 1
  -- minPage/maxPage: the cartridge greys the pages a context cannot reach --
  -- the move-learn flow opens on the moves pages only.  This port always
  -- offers whatever `self.pages` holds, so the range IS the page list.
  local minPage, maxPage = 0, count - 1
  local cell = pages.cell or 8
  local iw, ih = image:getDimensions()
  local quads = {}
  local function quad(tile, half)
    local key = tile * 2 + half
    if quads[key] then return quads[key] end
    local column = tile - (pages.first or 0x40)
    if column < 0 or column >= (pages.tiles or 13) then return nil end
    quads[key] = love.graphics.newQuad(column * cell, half * cell, cell, cell,
                                       iw, ih)
    return quads[key]
  end
  love.graphics.setColor(1, 1, 1, 1)
  for i = 0, count - 1 do
    -- the ROM's own order of tests, top to bottom
    local left
    if i < minPage then left = pages.beforeRange or 0x40
    elseif i > maxPage then left = pages.afterRange or 0x4A
    elseif i < current then left = pages.earlier or 0x46
    elseif i == current then
      left = (i == maxPage) and (pages.currentLast or 0x4B)
                            or (pages.current or 0x41)
    else
      left = (i == maxPage) and (pages.laterLast or 0x48)
                            or (pages.later or 0x43)
    end
    -- the two "outside the range" pairs repeat one tile; every other pair
    -- steps, which is what draws the pill's caps
    local right = (left == (pages.beforeRange or 0x40)
                   or left == (pages.afterRange or 0x4A)) and left or left + 1
    for half = 0, 1 do
      for k, tile in ipairs({ left, right }) do
        local q = quad(tile, half)
        if q then
          love.graphics.draw(image, q,
                             (pages.x or 88) + i * 2 * cell + (k - 1) * cell,
                             (pages.y or 0) + half * cell)
        end
      end
    end
  end
end

function Gen3SummaryMenu:drawHeader()
  if not self.hasArt then
    Font.drawBox(HEADER.tx, HEADER.ty, HEADER.tw, HEADER.th)
  end
  local mon, def = self.mon, self.def
  if not mon then return end
  local name = mon.nickname or (def and def.name) or tostring(mon.species)
  local title = self.pages[self.page] or ""
  if self.hasArt then
    -- THE PANEL, MEASURED.  Its picture box is the striped rectangle in the
    -- art: x 8..71, y 32..95, which is exactly 64 by 64 -- a Gen 3 front pic.
    -- The band above it holds the name and the one below holds the level, and
    -- both are read off the same picture rather than chosen.
    -- THE PANEL IS TWO WINDOWS, and the second one is not on every page.
    --
    --   window 18 (8,96) 72x16   the NICKNAME, on all four pages
    --   window 19 (8,112) 72x32  the SPECIES on its first row and
    --                            "Lv<n>" at x=24 with the gender at x=57 on
    --                            its second (08:$1C275E, $1C271E, $1C280C)
    --
    -- Window 19 sits at (8,112) and the two moves pages put their EFFECT box
    -- -- window 14, POWER/ACCURACY, or window 15, APPEAL/JAM -- at (8,120).
    -- Those overlap, so the cartridge cannot show both and hides window 19 on
    -- the moves pages.  Drawing it anyway is what put "Lv30" across POWER and
    -- ACCURACY, and across APPEAL and JAM over the contest hearts.
    --
    -- The HP line this used to print in the dex-number slot is gone with it:
    -- window 17 is (8,16) and 32 pixels wide, it holds a three-digit dex
    -- number and nothing else, and the SKILLS page already prints the same
    -- "17/104" in its own stat grid.
    local w = self:windows()
    local nameWin = w and w.labels[19]
    local bandWin = w and w.labels[20]
    if nameWin then
      putIn(nameWin, name, 0, 1, PLAIN)
    else
      put(name, PANEL_TEXT_X, (self:panelRows()), PLAIN)
    end
    if self:showsLevelBand() then
      if bandWin then
        local species = (def and def.name) or tostring(mon.species)
        putIn(bandWin, species, 0, 1, PLAIN)
        putIn(bandWin, ("Lv%d"):format(mon.level or 1), PANEL_LEVEL_X, 17,
              PLAIN)
        local mark = self:genderMark()
        if mark then
          putIn(bandWin, mark, PANEL_GENDER_X, 17,
                mark == "\u{2640}" and FEMALE or MALE)
        end
      else
        local _, levelY = self:panelRows()
        put(("Lv%d"):format(mon.level or 1), PANEL_TEXT_X + 24, levelY, PLAIN)
      end
    end
    put(title, COL_RIGHT - Font.width(title), 4, PLAIN)
    self:drawPagination()
    if self.pic then
      love.graphics.setColor(1, 1, 1, 1)
      -- every animation frame is the pic's own size, so the box placement is
      -- measured off the STILL and only the texture swaps
      local w, h = self.pic:getDimensions()
      local image = (self.picAnim and self.picAnim:image()) or self.pic
      self:drawMon(image,
                   PANEL_PIC_X + math.floor((PANEL_PIC_W - w) / 2),
                   PANEL_PIC_Y + math.max(0, PANEL_PIC_W - h))
    end
    return
  end
  put(name, 40, 10, PLAIN)
  put(("Lv%d"):format(mon.level or 1), 40, 24, PLAIN)
  -- the page name sits on the right of the header, where the cartridge's
  -- page indicator is
  put(title, GBA_W - 8 - Font.width(title), 10, PLAIN)
  if self.pic then
    love.graphics.setColor(1, 1, 1, 1)
    self:drawMon((self.picAnim and self.picAnim:image()) or self.pic,
                 PIC_X, PIC_Y)
  end
end

local MEMO_LINE_H = 12
-- what the cartridge's own template writes into each slot
local MEMO_SLOTS = { nature = "{NATURE}", level = "{LEVEL}",
                     location = "{LOCATION}" }

-- ---------------------------------------------------------------------------
-- THE INFO PAGE
--
-- THREE PANELS, and the cartridge's own art says which: the extracted
-- background has PROFILE, ABILITY and TRAINER MEMO printed on its three
-- heading bars, and the measured rows fall two, two and three inside them.
-- The port was drawing five rows of its own down that column -- DEX NO., NAME,
-- TYPE, OT, ID No. -- which put the third one straight through the ABILITY
-- heading and pushed the memo off the bottom of a 160-pixel screen entirely.
--
--   PROFILE       OT/ <name>          who caught it
--                 IDNo. <id>
--   ABILITY       <name>              and what it does, which is the only
--                 <description>       place in the whole game that says
--   TRAINER MEMO  <nature> nature,    three lines, chosen from eight
--                 met at Lv5,         templates -- see memoTemplate
--                 ROUTE 101.
--
-- The dex number, species and type move to the left panel, which on this page
-- has an empty band under the level for exactly them.  (The HP line the
-- header draws there belongs to the SKILLS page's stat block on the
-- cartridge and is suppressed here -- see drawHeader.)
-- ---------------------------------------------------------------------------

function Gen3SummaryMenu:typeText()
  local def = self.def
  local t1 = def and (def.type1 or (def.types and def.types[1]))
  local t2 = def and (def.type2 or (def.types and def.types[2]))
  if not t1 then return nil end
  local text = TypeChart.displayName and TypeChart.displayName(t1) or tostring(t1)
  -- a single-type species stores the same type TWICE on this cartridge, so
  -- the two are folded rather than printed as "GRASS/GRASS"
  if t2 and t2 ~= t1 then
    text = text .. "/" .. (TypeChart.displayName and TypeChart.displayName(t2)
                           or tostring(t2))
  end
  return text
end

function Gen3SummaryMenu:abilityDescription()
  local def, mon = self.def, self.mon
  local list = def and def.abilities
  if type(list) ~= "table" then return nil end
  local id = list[(mon and mon.abilitySlot) or 1] or list[1]
  local abilities = (self.game.data.constants or {}).abilities
  local record = id and abilities and abilities[id]
  local text = record and record.description
  return (type(text) == "string" and text ~= "") and text or nil
end

function Gen3SummaryMenu:drawInfo()
  local mon, def = self.mon, self.def
  local Y = self:rows()
  local labelX, valueX = self:cols()

  -- PROFILE -- ONE ROW, TWO WINDOWS.
  --
  -- This is where the overlap was.  Emerald's info page has TWO windows on
  -- row 32: the OT box at (88,32) 88 wide and the ID box at (176,32) 56 wide.
  -- The port read them as two ROWS and gave both the same y -- info[2] is at
  -- y=32 too -- so "OT/" and "ID No." printed on top of each other and the
  -- trainer's name printed on top of the number.
  --
  -- The cartridge:
  --   "OT/" at x=0 of the OT window (08:$1C2EFE), then the trainer's name at
  --   x = GetStringWidth("OT/") in the SAME window (08:$1C2F2C), coloured by
  --   the OT's gender;
  --   "IDNo." + five digits RIGHT-ALIGNED to 56 in the ID window
  --   (08:$1C2FBC), so the number ends at the panel's right edge.
  local w = self:windows()
  local otLabel = word(self.game, "ot", "OT/")
  local idText = (word(self.game, "idNo", "IDNo.")
                  .. (mon.otId and ("%05d"):format(mon.otId % 65536)
                      or "-----"))
  if w then
    putIn(w.info[1], otLabel, 0, 1, PLAIN)
    putIn(w.info[1], mon.ot or "?", Font.width(otLabel), 1, PLAIN)
    putIn(w.info[2], idText, { right = INFO_ID_RIGHT }, 1, PLAIN)
  else
    put(otLabel, labelX, Y[1], PLAIN)
    put(mon.ot or "?", valueX, Y[1], PLAIN)
    put(idText, labelX, Y[2], PLAIN)
  end

  -- ABILITY.  The name on one line and the sentence on the next; both come
  -- off the cartridge, and the sentence is the only explanation of an ability
  -- anywhere in the game.
  local ability = self:abilityName()
  if ability then put(ability, labelX, Y[3], PLAIN) end
  local blurb = self:abilityDescription()
  if blurb then
    -- the cartridge wraps this itself with a line break; the box is two rows
    -- and the second is where the break lands
    local first, rest = blurb:match("^(.-)\n(.*)$")
    put(first or blurb, labelX, Y[4], PLAIN)
    if rest then put(rest, labelX, Y[4] + MEMO_LINE_H, PLAIN) end
  end

  -- TRAINER MEMO
  for i, line in ipairs(self:memoLines()) do
    put(line, labelX, Y[4 + i] or (Y[5] + (i - 1) * MEMO_LINE_H), PLAIN)
  end

  -- ...AND THE TYPE ROW, which is on THIS side of the screen.
  --
  -- Reported from play, with a screenshot: the species name and
  -- "DRAGON/FLYING" were printed across the Pokemon's picture, and the types
  -- ran past the 80-pixel panel into the column beside it.  They were being
  -- drawn at the dex number's row plus 14 and plus 28 -- y=31 and y=45 -- and
  -- the picture box starts at y=32.
  --
  -- Neither belongs there.  The cartridge puts the SPECIES in the left panel's
  -- lower band, under the nickname (window 19's first row, drawn by
  -- drawHeader), and the TYPES in the right-hand column: window 9 at (88,48)
  -- prints "TYPE/" and the two type icons follow it on the same row.  That is
  -- the empty white band this page had between PROFILE and ABILITY.
  --
  -- The icons are sprites on hardware and this port has no sheet for them, so
  -- the type NAMES stand in beside the label -- which is what the Game Boy
  -- generations print anyway.
  if self.hasArt then
    local dex = def and def.dex
    local w = self:windows()
    local dexWin = w and w.labels[18]
    if dexWin then
      -- window 17 is (8,16) and 32 wide: it holds the three-digit number and
      -- nothing else (08:$1C268A prints only the number into it)
      putIn(dexWin, dex and ("%03d"):format(dex) or "---", 0, 1, PLAIN)
    else
      local _, _, dexY = self:panelRows()
      put(Strings("DEX NO."), PANEL_TEXT_X, dexY, PLAIN)
      put(dex and ("%03d"):format(dex) or "---",
          PANEL_TEXT_X + 40, dexY, PLAIN)
    end
    local typeWin = w and w.labels[10]
    local types = self:typeText()
    local label = word(self.game, "type", "TYPE/")
    if typeWin then
      putIn(typeWin, label, 0, 1, PLAIN)
      if types then
        putIn(typeWin, types, Font.width(label) + TYPE_GAP, 1, PLAIN)
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- THE TRAINER MEMO
--
-- Three lines at the bottom of the info page, and until now the port printed
-- one hand-typed one -- "<nature> nature." with a full stop the cartridge does
-- not put there.  Emerald's is built from EIGHT templates that come off the
-- cartridge (extractTrainerMemo), and WHICH ONE is used is the interesting
-- part: it is the only place in the game that tells the player where a
-- Pokemon came from, and the cartridge is careful not to overclaim.
--
--   met at Lv5, ROUTE 101.     you caught it, and the game watched you
--   hatched at Lv5, ROUTE 117. it came out of an egg -- met level ZERO
--   obtained in a trade.       someone gave it to you and there is no place
--   <nature> nature            nothing is known: a rental, or a save from
--                              before any of this was recorded
--
-- The fall-through to the bare template is deliberate and is not a stub: it
-- is what Emerald itself prints when it has no history to show, so a party
-- loaded from an older save reads as a Battle Frontier rental rather than as
-- a Pokemon that claims to have been met on whatever map you are standing on.
--
-- THE PLACE IS A REGION-MAP SECTION, not a map.  ROUTE 101 is eleven map ids
-- sharing one section; naming the map would print the id of whichever screen
-- the ball happened to land on.
-- ---------------------------------------------------------------------------

local function memoRecord(game)
  local consts = game and game.data and game.data.constants
  return consts and consts.gen3Memo or nil
end
Gen3SummaryMenu.memoRecord = memoRecord

-- The section NAME for a met location, which is stored the cartridge's way:
-- an index into the region map's own table.
function Gen3SummaryMenu:metPlace()
  local mon = self.mon
  local index = mon and tonumber(mon.metLocation)
  if not index then return nil end
  local consts = self.game and self.game.data and self.game.data.constants
  local sections = consts and consts.gen3MapSections
  local name = sections and sections[index]
  return (type(name) == "string" and name ~= "") and name or nil
end

-- IS THIS MON YOURS?  The cartridge's DoesMonOTMatchOwner: the OT name AND
-- the id, because a player called MAY meeting another player called MAY is
-- exactly the case the id is there to separate.  A mon whose OT is not yours
-- gets a different half of the memo, and that is the point of the block --
-- your game did not watch it be caught and does not claim it did.
function Gen3SummaryMenu:memoOwnMon()
  local mon, save = self.mon, self.game and self.game.save
  local player = save and save.player
  if not (mon and player) then return true end
  if mon.ot == nil and mon.otId == nil then return true end
  if mon.ot ~= nil and player.name ~= nil and mon.ot ~= player.name then
    return false
  end
  if mon.otId ~= nil and player.id ~= nil and mon.otId ~= player.id then
    return false
  end
  return true
end

-- Which of the eight the cartridge would choose, from the same facts
-- BufferMonTrainerMemo decides on: whose mon it is, whether there is a met
-- level at all, whether it is zero, and whether there is a place.
function Gen3SummaryMenu:memoTemplate()
  local record = memoRecord(self.game)
  local templates = record and record.templates
  if not templates then return nil end
  local mon = self.mon
  local level = mon and tonumber(mon.metLevel)
  local place = self:metPlace()
  if level == nil then
    -- nothing recorded: a rental, or a party from before any of this existed
    return templates.bare
  end
  if not self:memoOwnMon() then
    -- SOMEONE ELSE CAUGHT IT.  With a place, the cartridge still hedges --
    -- "probably met at" -- because the record travelled with the mon and was
    -- not witnessed here.  With none, there is nothing to hedge about.
    return place and templates.probablyMet or templates.trade
  end
  if level == 0 then
    -- zero is not missing data: it is the cartridge's flag for HATCHED
    return place and templates.hatched or templates.hatchedSomewhere
  end
  if not place then
    -- a level but nowhere to put it
    return templates.metSomewhere
  end
  return templates.met
end

function Gen3SummaryMenu:memoLines()
  local mon = self.mon
  if not mon then return {} end
  local record = self:natureRecord()
  local nature = record and (record.name or record.id) or mon.nature
  local template = self:memoTemplate()
  if not template then
    -- NO CARTRIDGE RECORD AT ALL -- a Gen 1/Gen 2 dataset, or an import that
    -- predates the stage.  One line, and no invented punctuation.
    return nature and { ("%s nature"):format(tostring(nature)) } or {}
  end
  if not nature then return {} end
  local filled = template
    :gsub(MEMO_SLOTS.nature, (tostring(nature):gsub("%%", "%%%%")))
    :gsub(MEMO_SLOTS.level, tostring(tonumber(mon.metLevel) or 0))
    :gsub(MEMO_SLOTS.location, (tostring(self:metPlace() or ""):gsub("%%", "%%%%")))
  local lines = {}
  for line in (filled .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  -- a template whose last line is empty (the bare one has no trailing break)
  while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
  return lines
end

local STAT_ROWS = {
  { key = "hp", label = "HP" },
  { key = "attack", label = "ATTACK" },
  { key = "defense", label = "DEFENSE" },
  { key = "spatk", label = "SP. ATK" },
  { key = "spdef", label = "SP. DEF" },
  { key = "speed", label = "SPEED" },
}

function Gen3SummaryMenu:drawSkills()
  local mon = self.mon
  local stats = mon and mon.stats or {}
  local Y = self:rows()
  local labelX, valueX, rightLabelX, rightValueX = self:cols()
  -- the six stat names come off the cartridge in ITS order (HP last); this
  -- screen lists HP first, so the labels are looked up by position rather
  -- than re-typed
  local fromRom = summaryText(self.game)
  local romStats = fromRom and fromRom.stats
  local romLabel = {}
  if type(romStats) == "table" and #romStats == 6 then
    romLabel.attack, romLabel.defense = romStats[1], romStats[2]
    romLabel.spatk, romLabel.spdef = romStats[3], romStats[4]
    romLabel.speed, romLabel.hp = romStats[5], romStats[6]
  end
  -- THE STATS GRID IS TWO COLUMNS OF THREE, which is what the art draws: the
  -- first three down the left half, the other three down the right, each with
  -- its value in its own column.  Six in a single column is what the port did
  -- before, and on the cartridge's background it ran straight off the panel.
  -- THE SIX LABELS ARE CENTRED IN THEIR COLUMN, and that is not a detail:
  -- HP is two letters and DEFENSE is seven, and left-aligning both put HP
  -- fourteen pixels left of where the cartridge draws it.  Emerald centres
  -- the left three in 42 pixels offset by 6 (08:$1C2986) and the right three
  -- in 36 offset by 2 (08:$1C29E6) -- the two label windows' own insets.
  local w = self:windows()
  local statY = { Y[2], Y[3], Y[4] }
  local LEFT_LABEL = { center = 42, plus = 6 }
  local RIGHT_LABEL = { center = 36, plus = 2 }
  for i, row in ipairs(STAT_ROWS) do
    local colour = (row.key == "hp") and PLAIN or self:statColour(row.key)
    local left = i <= 3
    local rowY = statY[left and i or (i - 3)] or Y[2]
    local label = romLabel[row.key] or Strings(row.label)
    local value
    if row.key == "hp" then
      value = ("%d/%d"):format(mon.hp or 0, stats.hp or 0)
    else
      value = tostring(stats[row.key] or 0)
    end
    if w then
      local labelWin = left and w.labels[11] or w.labels[12]
      local valueWin = left and w.skills[3] or w.skills[4]
      putIn(labelWin, label, left and LEFT_LABEL or RIGHT_LABEL,
            rowY - labelWin.y, colour)
      putIn(valueWin, value, left and 4 or 2, rowY - valueWin.y, colour)
    else
      put(label, left and labelX or rightLabelX, rowY, colour)
      put(value, left and valueX or rightValueX, rowY, colour)
    end
  end

  -- THE TOP ROW IS THE HELD ITEM AND THE RIBBON COUNT, which is what the
  -- cartridge's art prints on it -- the two heading bars there say ITEM and
  -- RIBBON.  This row used to draw the ABILITY name, which is a fact from a
  -- different page: the art puts ABILITY on the info page, in its own box,
  -- with its description under it.
  local held = mon and mon.item
  local items = (self.game.data or {}).items
  local heldDef = held and items and items[held]
  put((heldDef and (heldDef.name or heldDef.id)) or (held and tostring(held))
        or Strings("NONE"), labelX, Y[1], PLAIN)
  local ribbons = 0
  for _ in pairs((mon and mon.ribbons) or {}) do ribbons = ribbons + 1 end
  put(tostring(ribbons), rightLabelX, Y[1], PLAIN)

  -- THE TWO NUMBERS ARE RIGHT-ALIGNED, and they are not in the label's
  -- window.  PrintExpPointsNextLevel (08:$1C38C0) right-aligns each to 42
  -- pixels inside the EXP window and then adds 2, so both end at the same
  -- column however many digits they have; this port printed them at the
  -- left edge of the RIGHT-HAND STAT LABEL window, 58 pixels away and on top
  -- of the panel's own edge.
  local expLabels = w and w.labels[13]
  local expValues = w and w.skills[5]
  local EXP_VALUE = { right = 42, plus = 2 }
  local remaining = self:expToNext()
  if w then
    putIn(expLabels, word(self.game, "expPoints", "EXP. POINTS"), 6, 1, PLAIN)
    putIn(expValues, tostring(mon.exp or 0), EXP_VALUE, 1, PLAIN)
    putIn(expLabels, word(self.game, "nextLevel", "NEXT LV."), 6, 17, PLAIN)
    putIn(expValues, remaining and tostring(remaining) or "-", EXP_VALUE, 17,
          PLAIN)
  else
    put(word(self.game, "expPoints", "EXP. POINTS"), labelX, Y[5], PLAIN)
    put(tostring(mon.exp or 0), rightLabelX, Y[5], PLAIN)
    put(word(self.game, "nextLevel", "NEXT LV."), labelX, Y[6], PLAIN)
    put(remaining and tostring(remaining) or "-", rightLabelX, Y[6], PLAIN)
  end
end

function Gen3SummaryMenu:abilityName()
  local def, mon = self.def, self.mon
  local list = def and def.abilities
  if type(list) ~= "table" then return nil end
  local slot = (mon and mon.abilitySlot) or 1
  local id = list[slot] or list[1]
  if not id then return nil end
  local abilities = (self.game.data.constants or {}).abilities
  local record = abilities and abilities[id]
  return (record and (record.name or record.id)) or tostring(id)
end

-- HOW MUCH EXPERIENCE IS LEFT, from the species' own growth curve.
--
-- The curve is the cartridge's -- six of them, 101 levels each, read by the
-- extractor -- so this is a subtraction rather than a formula.
function Gen3SummaryMenu:expToNext()
  local mon, def = self.mon, self.def
  if not (mon and def) then return nil end
  local level = mon.level or 1
  if level >= ((self.game.data.constants or {}).maxLevel or 100) then return 0 end
  local ok, Growth = pcall(require, "src.pokemon.Growth")
  if not ok or not Growth or not Growth.expForLevel then return nil end
  local rates = (self.game.data.constants or {}).experienceTables
  local ok2, need = pcall(Growth.expForLevel, def.growthRate, level + 1, rates)
  if not ok2 or type(need) ~= "number" then return nil end
  return math.max(0, need - (mon.exp or 0))
end

-- THE APPEAL AND JAM HEARTS.
--
-- Reported from play: they were not showing.  They were being printed as
-- asterisks, because nothing had located what the cartridge actually draws --
-- and what it draws is not text.  DrawContestMoveHearts (08:$1C2438) writes
-- eight tile entries per row into the background tilemap, four to a line over
-- two lines, at pixel (48,120) for APPEAL and (48,136) for JAM, choosing
-- between a filled and an empty tile per position.  extractSummaryScreen now
-- cuts those four tiles out of the same sheet the pages come from.
--
-- How many are filled is the value divided by ten -- an APPEAL of 40 is four
-- hearts -- and the ROM's `cmp #$FF` guard means an effect with no value at
-- all draws eight EMPTY hearts rather than none: the row is always there.
--
-- With no strip in the dataset (a cache imported before this existed) the
-- asterisks stand, so an old import still says how many there are.
local HEART_CELL = 8

function Gen3SummaryMenu:heartArt()
  local record = (self.game.data.constants or {}).gen3Summary
  local hearts = record and record.hearts
  if not (hearts and hearts.image) then return nil end
  if self._heartImage == nil then
    local ok, image = pcall(function()
      return require("src.render.Assets").image(hearts.image)
    end)
    self._heartImage = (ok and image) or false
  end
  if not self._heartImage then return nil end
  return hearts, self._heartImage
end

function Gen3SummaryMenu:drawHearts(def)
  local hearts, image = self:heartArt()
  local unit = ((self.game.data.constants or {}).gen3Contest or {}).heartUnit
    or (hearts and hearts.unit) or 10
  if not hearts then
    -- the old text stand-in, so a dataset with no strip still shows a count
    local function stars(value)
      local n = math.floor((tonumber(value) or 0) / unit)
      return n > 0 and string.rep("*", n) or "-"
    end
    local w = self:windows()
    local y = w and (w.labels[16].y + 1) or 121
    put(stars(def.contestAppeal), 48, y, PLAIN)
    put(stars(def.contestJam), 48, y + 16, PLAIN)
    return
  end

  local order = {}
  for i, key in ipairs(hearts.order or {}) do order[key] = i - 1 end
  local cell = hearts.cell or HEART_CELL
  local iw, ih = image:getDimensions()
  local quads = {}
  local function quad(key)
    if quads[key] then return quads[key] end
    local index = order[key]
    if not index then return nil end
    quads[key] = love.graphics.newQuad(index * cell, 0, cell, cell, iw, ih)
    return quads[key]
  end

  love.graphics.setColor(1, 1, 1, 1)
  local perRow = hearts.perRow or 4
  local max = hearts.max or 8
  local function row(spot, value, filledKey, emptyKey)
    if not spot then return end
    -- $FF is the cartridge's "this effect has no rating": every heart empty
    local raw = tonumber(value)
    local filled = (raw and raw ~= 0xFF) and math.floor(raw / unit) or 0
    for i = 0, max - 1 do
      local q = quad(i < filled and filledKey or emptyKey)
      if q then
        love.graphics.draw(image, q,
                           spot.x + (i % perRow) * cell,
                           spot.y + math.floor(i / perRow) * cell)
      end
    end
  end
  row(hearts.appeal, def.contestAppeal, "appealFilled", "appealEmpty")
  row(hearts.jam, def.contestJam, "jamFilled", "jamEmpty")
end

-- THE DESCRIPTION HAS ITS OWN BOX, and it is not the move list's column.
--
-- Reported from play, with a screenshot: "descriptions going off of the side
-- of the screen instead of being left aligned to the description box".  Both
-- pages printed the sentence at `labelX` -- the move-NAME column, x=120 --
-- when the DESCRIPTION window is (80,120) 160x32 with its text six pixels in
-- (08:$1C3E7E, $1C3EE8, $1C3F1C, $1C417C all pass x=6).  So every line began
-- 34 pixels right of its box and ran off the screen.
--
-- The cartridge writes these as ONE string with the line break already in it,
-- printed at y=1; the printer wraps it to y=17 itself.  The break is honoured
-- rather than re-wrapped, and the window clips whatever still does not fit.
local DESCRIPTION_X = 6

function Gen3SummaryMenu:drawDescription(text, fallbackY1, fallbackY2)
  if type(text) ~= "string" or #text == 0 then return end
  local w = self:windows()
  local box = w and w.moves[3]
  local line = 0
  for part in (text .. "\n"):gmatch("([^\n]*)\n") do
    if #part > 0 and line < 2 then
      if box then
        putIn(box, part, DESCRIPTION_X, 1 + line * 16, PLAIN)
      else
        put(part, DESCRIPTION_X, line == 0 and fallbackY1 or fallbackY2, PLAIN)
      end
      line = line + 1
    end
  end
end

function Gen3SummaryMenu:drawMoves(contest)
  local mon = self.mon
  local moves = (mon and mon.moves) or {}
  local data = self.game.data
  local Y = self:rows()
  local labelX, valueX = self:cols()
  -- the PP column is its own window on the cartridge; without one, the place
  -- this drew before
  local w = self:windows()
  local ppX = w and w.moves[2].x or MOVE_PP_X
  local y = Y[1]
  local picking = type(self.choose) == "table"

  -- ONE ROW, THE WAY THE CARTRIDGE PRINTS IT.
  --
  -- The name goes at x=0 of the 72-wide name window; the PP goes RIGHT-ALIGNED
  -- to 44 pixels inside the 48-wide PP window beside it (the ROM's
  -- `mov r2,#44 / bl GetStringRightAlignXOffset`), which is what puts every
  -- move's PP in one column however many digits it has.  Left-aligning it at
  -- the window's near edge -- which is what this did -- pushed a three-digit
  -- pair straight out of the box.
  --
  -- The word "PP" is a SINGLE GLYPH on this cartridge, not two letters: the
  -- template at $861CE97 is `{SYM 6}{VAR1}/{VAR2}` and symbol 6 is the PP
  -- ligature.  It is part of the string being right-aligned, so it moves with
  -- the numbers rather than sitting apart from them.
  local function row(i, name, right, colour)
    local ry = (Y[i] or (Y[1] + (i - 1) * MOVE_ROW_PITCH)) - (w and w.moves[1].y or 0)
    if w then
      putIn(w.moves[1], name, 0, ry, colour or PLAIN)
      if right then
        putIn(w.moves[2], right, { right = MOVE_PP_RIGHT },
              (Y[i] or Y[1]) - w.moves[2].y, colour or PLAIN)
      end
    else
      put(name, labelX, Y[i] or Y[1], colour or PLAIN)
      if right then put(right, ppX, Y[i] or Y[1], colour or PLAIN) end
    end
  end

  for i = 1, 4 do
    local slot = moves[i]
    local id = (type(slot) == "table") and slot.id or slot
    if id then
      local def = data.moves and data.moves[id]
      local right
      if contest then
        -- the contest side of a move: the category it appeals in, which is
        -- the cartridge's own
        local category = def and (def.contestCategory or def.contestType)
        right = category and tostring(category) or "-"
      else
        local pp = (type(slot) == "table") and slot.pp or (def and def.pp)
        right = ("%s%s/%s"):format(ppSymbol(),
                                   tostring(pp or "-"),
                                   tostring(def and def.pp or "-"))
      end
      row(i, (def and def.name) or tostring(id), right)
    else
      row(i, "-", nil)
    end
    -- the cursor marks the row the bottom of the page is describing, whether
    -- it got there from the learn flow or from A on the moves page
    if (picking or self.moveSelect) and i == (self.moveIndex or 1) then
      love.graphics.setColor(1, 1, 1, 1)
      Font.drawCode(CHOOSE_CURSOR, labelX - 10, Y[i] or Y[1])
    elseif self.moveSwapFrom == i then
      love.graphics.setColor(1, 1, 1, 1)
      Font.drawCode(HELD_CURSOR, labelX - 10, Y[i] or Y[1])
    end
  end
  y = Y[8] or (Y[1] + 4 * MOVE_ROW_PITCH)

  -- ...AND THE FIFTH ROW, which is the move being offered.  Picking it is
  -- how the cartridge says "do not learn it" -- there is no CANCEL row on
  -- this screen, the new move IS the way out.  The ROM prints it at y=65,
  -- which is the same 16-pixel step continued, not a row of its own.
  if picking then
    local id = self.choose.move
    local def = id and data.moves and data.moves[id]
    local name = (def and def.name) or tostring(id or "-")
    if w then
      putIn(w.moves[1], name, 0, y - w.moves[1].y, PLAIN)
      if not contest and def then
        putIn(w.moves[2],
              ("%s%s/%s"):format(ppSymbol(), tostring(def.pp or "-"),
                                 tostring(def.pp or "-")),
              { right = MOVE_PP_RIGHT }, y - w.moves[2].y, PLAIN)
      end
    else
      put(name, labelX, y, PLAIN)
    end
    if (self.moveIndex or 1) >= 5 then
      love.graphics.setColor(1, 1, 1, 1)
      Font.drawCode(CHOOSE_CURSOR, labelX - 10, y)
    end
  end

  -- THE CONTEST PAGE'S OWN BOTTOM HALF, which was blank.  APPEAL and JAM are
  -- stored in tenths -- 40 is four hearts -- and the sentence is the effect's,
  -- shared by every move that has that effect.
  if contest then
    local slot = moves[self:selectedMove()]
    local id = (type(slot) == "table") and slot.id or slot
    local def = id and data.moves and data.moves[id]
    if def and self.hasArt then
      local y2 = Y[5] or ((PAGE.ty + 1) * 8)
      local y3 = Y[6] or (y2 + ROW_PITCH)
      local box = w and w.labels[16]
      putIn(box or nil, word(self.game, "appeal", "APPEAL"), 0, 1, PLAIN)
      putIn(box or nil, word(self.game, "jam", "JAM"), 0, 17, PLAIN)
      if not box then
        put(word(self.game, "appeal", "APPEAL"), 8, y2, PLAIN)
        put(word(self.game, "jam", "JAM"), 8, y3, PLAIN)
      end
      self:drawHearts(def)
      self:drawDescription(def.contestDescription, y2, y3)
    end
  end

  if not contest then
    -- THE MOVE THE BOTTOM OF THE PAGE IS ABOUT.  This read moves[1] and
    -- nothing else, so POWER, ACCURACY and the sentence described the first
    -- move however far down the list the cursor was -- which is what "i cant
    -- scroll through the moves" looks like once there IS a cursor.
    local slot = moves[self:selectedMove()]
    local id = (type(slot) == "table") and slot.id or slot
    local def = id and data.moves and data.moves[id]
    if def then
      -- THE BOTTOM OF THIS PAGE IS TWO BOXES, and the art says which is
      -- which: a narrow one at the far left (x 4..76) and a wide one beside
      -- it (x 84..238).  POWER and ACCURACY go in the narrow one; what the
      -- move DOES goes in the wide one, which is the biggest box on the page
      -- and was empty.
      local y2 = Y[5] or ((PAGE.ty + 1) * 8)
      local y3 = Y[6] or (y2 + ROW_PITCH)
      if self.hasArt then
        -- POWER and ACCURACY share one window -- 14, at (8,120) 72x32 -- with
        -- the two labels sixteen apart inside it.  APPEAL and JAM are window
        -- 15 at the same corner, forty wide, which is why the contest page's
        -- numbers sit further left.
        -- x=0 for the two labels and x=53 for the two numbers, both
        -- window-relative (08:$1C2A66/$1C2A76 and 08:$1C3CB8/$1C3CF8).  The
        -- numbers were at +40 here, thirteen pixels left of their column.
        local box = w and w.labels[15]
        putIn(box, word(self.game, "power", "POWER"), 0, 1, PLAIN)
        putIn(box, tostring(def.power or "---"), POWER_VALUE_X, 1, PLAIN)
        putIn(box, word(self.game, "accuracy", "ACCURACY"), 0, 17, PLAIN)
        putIn(box, tostring(def.accuracy or "---"), POWER_VALUE_X, 17, PLAIN)
      else
        put(word(self.game, "power", "POWER"), labelX, y2, PLAIN)
        put(tostring(def.power or "---"), MOVE_PP_X, y2, PLAIN)
        put(word(self.game, "accuracy", "ACCURACY"), labelX, y3, PLAIN)
        put(tostring(def.accuracy or "---"), MOVE_PP_X, y3, PLAIN)
      end
      -- The cartridge writes the description as two lines with the break
      -- already in it, so the break is honoured rather than re-wrapped.
      if self.hasArt then
        self:drawDescription(def.description, y2, y3)
      end
    end
  end
end

function Gen3SummaryMenu:draw()
  love.graphics.setColor(0.20, 0.42, 0.36, 1)
  love.graphics.rectangle("fill", 0, 0, GBA_W, GBA_H)
  love.graphics.setColor(1, 1, 1, 1)

  -- THE CARTRIDGE'S OWN PAGE, when the cache carries it.  The panel goes down
  -- first because the other three pages leave its cells transparent for it.
  local page = artFor(self.game, ART_BY_PAGE[self.page] or "info")
  self.hasArt = page ~= nil
  if page then
    local panel = artFor(self.game, "panel")
    love.graphics.setColor(1, 1, 1, 1)
    if panel then love.graphics.draw(panel, 0, 0) end
    love.graphics.draw(page, 0, 0)
  end

  self:drawHeader()
  if not self.hasArt then
    Font.drawBox(PAGE.tx, PAGE.ty, PAGE.tw, PAGE.th)
  end

  if not self.mon then
    put(Strings("No POKéMON."), LABEL_X, (PAGE.ty + 1) * 8, PLAIN)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  if self.page == 1 then self:drawInfo()
  elseif self.page == 2 then self:drawSkills()
  elseif self.page == 3 then self:drawMoves(false)
  else self:drawMoves(true) end

  love.graphics.setColor(1, 1, 1, 1)
end

Gen3SummaryMenu.STAT_ROWS = STAT_ROWS
Gen3SummaryMenu.FALLBACK_PAGES = FALLBACK_PAGES

return Gen3SummaryMenu
