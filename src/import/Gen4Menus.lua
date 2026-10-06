-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum): the main menu, and the two window frames every menu in the
-- game is drawn out of.
--
-- Everything here is transcribed from the cartridge rather than designed.  The
-- layout numbers are `sOptions` and the loop in main_menu.c; the frame tile
-- orders are `DrawStandardWindowFrame` and `DrawMessageBoxFrame` in
-- render_window.c; the strings are message bank 550, confirmed by reading it
-- out of this ROM (entry 0 is CONTINUE, entry 1 is NEW GAME, entry 12 is
-- PLAYER -- the order the game's own table expects).
--
-- WHY THE FRAME ORDERS ARE WRITTEN OUT RATHER THAN GUESSED.  Platinum's standard
-- frame is nine tiles and IS an ordinary nine-slice; its dialogue frame is
-- EIGHTEEN, and eighteen reads equally well as 3 wide by 6 tall (two stacked
-- frames) or 6 wide by 3 tall (one frame with fat caps).  Both produce a
-- rectangle rather than an error, and only one of them is a box.  It is 6 by 3,
-- and the cartridge says so outright in the two Bg_FillTilemapRect runs below
-- rather than leaving it to be inferred from what the tiles look like.

local Gen4Menus = {}

Gen4Menus.WINFRAME = "/graphic/pl_winframe.narc"

-- ---------------------------------------------------------------------------
-- The two frames
-- ---------------------------------------------------------------------------

-- THE STANDARD WINDOW FRAME -- every menu, every choice box.  Nine tiles,
-- three across, and DrawStandardWindowFrame places them:
--
--     +0   +1 (repeated across the width)   +2
--     +3   [the window's own content]       +5
--     +6   +7 (repeated across the width)   +8
--
-- `tile + 4` is never drawn: the interior is the window's text bitmap, not a
-- frame tile.  That is exactly the engine's own nine-slice contract, so a
-- standard frame needs no new drawing code at all -- only the sheet, three
-- tiles wide, in member order.
Gen4Menus.STANDARD_TILES_WIDE = 3
Gen4Menus.STANDARD_TILES = 9

-- The two of them, in the order LoadStandardWindowTiles chooses between:
-- STANDARD_WINDOW_SYSTEM first, the field variant second.  `standard_field`
-- carries no palette of its own and borrows the system one, which is a fact
-- about the archive and not a fallback this module invented.
Gen4Menus.STANDARD = {
  { name = "standard_system", palette = "standard_system" },
  { name = "standard_field",  palette = "standard_system" },
}

-- THE DIALOGUE FRAME -- eighteen tiles, six across.  It is a nine-slice with
-- UNEQUAL CAPS: two tiles on the left and three on the right, so it reaches one
-- and two tiles past the window it frames.  DrawMessageBoxFrame, with the
-- window at (x, y) and size (width, height) in tiles:
--
--   row y-1         : +0 at x-2, +1 at x-1, +2 across width, +3 +4 +5 at x+width..+2
--   rows y..y+h-1   : +6 at x-2, +7 at x-1, [content], +9 +10 +11 at x+width..+2
--   row y+height    : +12 at x-2, +13 at x-1, +14 across width, +15 +16 +17
--
-- Read as a grid that is the whole point: it is SIX COLUMNS BY THREE ROWS, the
-- rows start at 0, 6 and 12, and within a row the columns are +0, +1, +2
-- repeated across the width, then +3, +4, +5.  One rule, every row -- which is
-- why the eighteen look like two unrelated halves until it is written down.
--
-- `tile + 8` -- the middle row's repeating column -- is the one member of the
-- eighteen the cartridge never places, because the window's own text bitmap
-- covers exactly that region.  This engine has no separate window bitmap and
-- draws its text straight onto the box, so it DOES place that tile, and the
-- result is the same picture: tile 8 is the interior.  Its colour is sampled
-- anyway, as the fill for a box too small to tile.
Gen4Menus.MESSAGE_BOX_TILES = 18
Gen4Menus.MESSAGE_BOX_COUNT = 20
Gen4Menus.MESSAGE_BOX_FILL_TILE = 8

-- Where the fill tile sits once the eighteen are laid out in one row, which is
-- the shape src/render/Font.lua reads a dialogue strip in.
Gen4Menus.FILL_SAMPLE_X = Gen4Menus.MESSAGE_BOX_FILL_TILE * 8 + 4
Gen4Menus.FILL_SAMPLE_Y = 4

-- Member name for frame n (0-19).  GetMessageBoxTilesNARCMember is
-- `message_box_00_NCGR + frame`, so the names run consecutively and the
-- palettes run alongside them one-for-one.
function Gen4Menus.messageBoxName(frame)
  return ("message_box_%02d"):format(frame)
end

-- ---------------------------------------------------------------------------
-- The main menu
-- ---------------------------------------------------------------------------

-- Message bank 550 (TEXT_BANK_MAIN_MENU_OPTIONS), read out of this cartridge:
-- 21 entries, and every index below was confirmed against the decoded text
-- rather than taken from the header alone.
Gen4Menus.BANK = 550

-- Bank 14 (TEXT_BANK_MAIN_MENU_ALERTS): six entries, the last of which is the
-- "there is already another saved game file" warning NEW GAME arms.
Gen4Menus.ALERT_BANK = 14
Gen4Menus.ALERT_NEW_GAME = 5

Gen4Menus.TEXT = {
  continue = 0, newGame = 1, mysteryGift = 2, rangerLink = 3,
  pedometer = 9, connectToWii = 10, wfcSettings = 11,
  player = 12, time = 13, pokedex = 14, badges = 15,
  playerName = 16, playTime = 17, seenCount = 18, badgeCount = 19,
  wiiMessageSettings = 20,
}

-- WHICH ROWS THIS PORT OFFERS.
--
-- Platinum's own menu has eight, and six of them are link features that do not
-- exist here: Mystery Gift, the Ranger link, GBA migration, the two Wii rows
-- and the Wi-Fi settings.  Offering a row that cannot do anything is worse than
-- not offering it, so the list is the two that work.
--
-- OPTION IS THIS ENGINE'S ADDITION AND IS MARKED AS ONE.  Platinum has no
-- OPTION row on its main menu -- text speed and the frame live in the in-game
-- START menu -- but every other title this engine boots offers one before a
-- save exists, and a player who wants to change the text speed before starting
-- has nowhere else to go.  It is listed last, after the cartridge's own two.
Gen4Menus.ROWS = {
  { id = "continue", text = 0,   lines = 5, fromCartridge = true },
  { id = "newGame",  text = 1,   lines = 1, fromCartridge = true },
  { id = "options",  text = nil, lines = 1, fromCartridge = false,
    fallback = "OPTION" },
}

-- The CONTINUE window's four label rows, in the order sContinueOptionStringsIDs
-- lists them.  Index 0 of that array is "Continue" itself, which the window
-- title prints, so the labelled rows start at 1.
Gen4Menus.CONTINUE_ROWS = {
  { label = 12, value = "playerName" },
  { label = 13, value = "playTime" },
  { label = 15, value = "badgeCount" },
  -- The dex row is skipped entirely until the Pokedex is obtained, which is a
  -- `continue` in the cartridge's loop rather than a blank line.
  { label = 14, value = "seenCount", needsPokedex = true },
}

-- Layout, in tiles unless the name says pixels.  From main_menu.c:
--
--   MainMenuUtil_ShowWindowAtPos(..., 3, nextOptionY, ...)  -- x = 3
--   OPTION_WINDOW_WIDTH 26
--   int nextOptionY = 1;
--   nextOptionY += option->height + 2;   // "Add 2 to account for the window border"
--   height = TEXT_LINES_TILES(n)          // n * 2, since MAX_LETTER_HEIGHT is 16
--   CONTINUE_WINDOW_MARGIN 32             // pixels, both the left inset and the
--                                         // right margin a value is aligned to
Gen4Menus.LAYOUT = {
  optionX = 3,
  optionWidth = 26,
  firstY = 1,
  gap = 2,
  lineTiles = 2,
  linePixels = 16,
  margin = 32,
}

-- BACKGROUND_COLOR and UNFOCUSED_OPTION_BG_COLOR, as GX_RGB five-bit
-- components.  Kept in the cartridge's own units so the conversion happens in
-- one place instead of being rounded twice.
Gen4Menus.COLORS = {
  background = { 12, 12, 31 },
  unfocused = { 26, 26, 26 },
}

-- GX_RGB (0-31 per channel) to the 0-1 triple LOVE draws with.
function Gen4Menus.rgb(c)
  return { (c[1] or 0) / 31, (c[2] or 0) / 31, (c[3] or 0) / 31 }
end

-- ---------------------------------------------------------------------------
-- The OPTIONS screen
-- ---------------------------------------------------------------------------

-- Message bank 220 (TEXT_BANK_OPTIONS_MENU): 53 entries, read out of this
-- cartridge and checked entry by entry -- 0 is OPTIONS, 3 is TEXT SPEED, 10-12
-- are SLOW/MID/FAST, 22-41 are TYPE 1 to TYPE 20, 43-48 are the one-line
-- descriptions that sit above the list.
Gen4Menus.OPTIONS_BANK = 220
Gen4Menus.OPTIONS_TITLE = 0

-- THE VALUE ORDER IS THE CARTRIDGE'S AND IT IS NOT GEN 3'S.
--
-- `OPTIONS_SOUND_MODE_STEREO = 0, OPTIONS_SOUND_MODE_MONO` -- Platinum lists
-- STEREO first, Emerald lists MONO first.  A screen that copied the Gen 3 row
-- would put the right two words in the wrong order, store the wrong one, and
-- look completely correct doing it.  Every row below is the enum's order in
-- constants/game_options.h, not a reading of what looks natural.
--
-- `values` are bank indices; `description` is the line the screen shows above
-- the list while that row is selected.
Gen4Menus.OPTION_ROWS = {
  { key = "textSpeed",   label = 3, values = { 10, 11, 12 }, description = 43 },
  { key = "battleScene", label = 4, values = { 13, 14 },     description = 44 },
  { key = "battleStyle", label = 5, values = { 15, 16 },     description = 45 },
  { key = "sound",       label = 6, values = { 17, 18 },     description = 46 },
  { key = "buttonMode",  label = 7, values = { 19, 20, 21 }, description = 47 },
  -- TYPE 1 .. TYPE 20, one bank entry each rather than a number formatted into
  -- a word: the cartridge spells all twenty out and two of the languages it
  -- ships in do not put the digit last.
  { key = "frame",       label = 8, values = "frames",       description = 48 },
  { key = "close",       label = 42, values = nil,           description = 52 },
}

Gen4Menus.FRAME_FIRST = 22
Gen4Menus.FRAME_LAST = 41

-- CONFIRM and its dialog are extracted and deliberately NOT offered as a row.
-- Platinum stages the changes and applies them on CONFIRM; this engine applies
-- each change as it is made, the way every other OPTION screen in it does, so a
-- CONFIRM row would either do nothing or promise a staging model that is not
-- there.  The strings are kept because the day the staging model exists they
-- are what it should say.
Gen4Menus.OPTIONS_CONFIRM = { label = 9, dialog = 49, yes = 50, no = 51 }

-- ---------------------------------------------------------------------------
-- Choosing a starter
-- ---------------------------------------------------------------------------

-- Bank 360 (8 entries), read out of this cartridge: 0 is "Look!  These are
-- Poke Balls!", 1-3 are the three offers in the order the briefcase lays them
-- out, and 7 is "Now choose!".  Entries 4-6 are blank in this language -- the
-- bottom screen's labels, which the hardware draws and this port has no second
-- screen for yet.
-- ---------------------------------------------------------------------------
-- The START MENU
-- ---------------------------------------------------------------------------

-- THE HALF OF THE ORIGINAL BRIEF THAT WAS STILL A DESIGN.  "instead of showing
-- the start menu on the bottom screen have a start menu on the main screen like
-- the other games have the choice to switch between the two styles."
--
-- Bank 367 (TEXT_BANK_START_MENU), and the order is `StartMenu_MakeOptionList`'s
-- rather than the enum's -- the two differ, and taking the enum would put
-- RETIRE and CHAT in the wrong place.  The list is built RETIRE, CHAT, POKEDEX,
-- POKEMON, BAG, TRAINER CASE, SAVE, OPTIONS, EXIT, each added only if its hide
-- flag is clear; in the ordinary field the first two are hidden, so what a
-- player sees is the last seven.
--
-- THERE IS NO POKETCH ROW, and that is worth stating because it is the thing a
-- reader expects to find: the Poketch is always on the bottom screen in
-- Platinum and is never a start-menu entry.
--
-- TRAINER CASE IS THE PLAYER'S NAME.  Its bank entry is `{STRVAR_1 3, 0, 0}` --
-- a template, not a word -- and `StartMenu_InitMenu` fills it with
-- `StringTemplate_SetPlayerName`.  Printing the entry raw puts a control code
-- on the menu.
Gen4Menus.START_BANK = 367
Gen4Menus.START_ROWS = {
  { id = "retire",      text = 8, icon = 8, hidden = true },
  { id = "chat",        text = 7, icon = 7, hidden = true },
  { id = "pokedex",     text = 0, icon = 0 },
  { id = "pokemon",     text = 1, icon = 1 },
  { id = "bag",         text = 2, icon = 2, femaleIcon = 9 },
  { id = "trainerCase", text = 3, icon = 3, playerName = true },
  { id = "save",        text = 4, icon = 4 },
  { id = "options",     text = 5, icon = 5 },
  { id = "exit",        text = 6, icon = 6 },
}

-- WHICH ICON IS WHICH, and it is not a guess: `animIdx = option *
-- ICON_ANIM_COUNT` with ICON_ANIM_COUNT = 3, so each group of three animations
-- (none / swell / wiggle -- they are scale animations of one picture, not three
-- pictures) belongs to one option in ENUM order.  The one exception is spelled
-- out in the same function: a FEMALE player's BAG uses group 9.
--
-- That is also why the icon sheet has TEN cells for NINE options, which is an
-- independent confirmation rather than a restatement: nine options plus the
-- second satchel is exactly ten.
Gen4Menus.START_ICONS = 10

-- Where it sits, from `StartMenu_InitMenu` and `sSpriteTemplates`:
--
--   Window_Add(..., BG_LAYER_MAIN_3, 20, 1, 11, optionCount * 3, ...)
--   the icon sprite at x = 174, y = 20 + 24 * i
--   the cursor sprite at x = 204, y = 20 + 24 * i
--
-- Tile (20, 1) is pixel (160, 8) and eleven tiles is 88 wide; three tiles per
-- option is the 24-pixel pitch the two sprite columns already use, which is the
-- two statements agreeing.  Both sprite x values are CENTRES.
Gen4Menus.START_LAYOUT = {
  panelX = 20 * 8, panelY = 1 * 8,
  panelW = 11 * 8, rowTiles = 3,
  pitch = 24,
  iconX = 174, cursorX = 204, firstY = 20,
}

Gen4Menus.STARTER_BANK = 360
Gen4Menus.STARTER_TEXT = {
  theseArePokeBalls = 0, nowChoose = 7,
}

-- The three, in the briefcase's own left-to-right order, each with the model
-- that holds it.  `choose_starter_app.c` names the species outright
-- (STARTER_OPTION_0 = SPECIES_TURTWIG and so on) and loads the ball models at
-- members 3, 5 and 7; the offer text is entry 1, 2 and 3 of the bank, in the
-- same order, which is the cross-check that the three lists line up.
Gen4Menus.STARTERS = {
  { species = 387, model = "psel_mb_a", text = 1, expect = "TURTWIG" },
  { species = 390, model = "psel_mb_b", text = 2, expect = "CHIMCHAR" },
  { species = 393, model = "psel_mb_c", text = 3, expect = "PIPLUP" },
}

-- ---------------------------------------------------------------------------
-- The party screen
-- ---------------------------------------------------------------------------

-- BANK 453, and it is the bank the port needed before it could teach a TM in
-- Sinnoh at all.
--
-- HOW IT WAS FOUND, which is the boring way and the right one: pokeplatinum's
-- `generated/text_banks.txt` lists TEXT_BANK_PARTY_MENU on line 454, and that
-- file's ZERO-BASED line numbers are the cartridge's bank ids -- the same rule
-- every other bank in this file was taken from.
--
-- CONFIRMED AGAINST THE CARTRIDGE rather than against the list: bank 453
-- decodes to 205 entries, which is exactly the count in
-- res/text/party_menu.json, and entry for entry -- 33 "Teach which Pokemon?",
-- 145 "SWITCH", 154 "ENTER", 169..174 FIRST..SIXTH, 175 "ABLE!", 176
-- "UNABLE!", 177 "LEARNED", 200 "CONFIRM".
--
-- PLATINUM SAYS "UNABLE!", NOT "NOT ABLE".  Emerald's word is NOT ABLE and
-- Gen 1's is too, so a screen that reused either would be showing a word this
-- cartridge does not use, with an exclamation mark missing from the other two.
Gen4Menus.PARTY_BANK = 453
Gen4Menus.PARTY_ENTRIES = 205

Gen4Menus.PARTY_TEXT = {
  -- the question along the bottom, one per reason the screen was opened
  choose = 29, moveWhere = 30, giveTo = 31, useOn = 32,
  teachWhich = 33, chooseAndConfirm = 34,
  -- the CANCEL button's label, the gender symbols on a panel, and the
  -- question while the submenu is open ("Do what with\n{nickname}?")
  cancelButton = 1, male = 27, female = 28, promptPokemon = 37,
  promptItem = 38,
  -- the item submenu
  give = 160, take = 161,
  -- the submenu
  switch = 145, summary = 146, item = 147, mail = 148,
  mailRead = 149, mailTake = 150, mailStore = 151, cancel = 152,
  enter = 154, noEntry = 155, confirm = 200,
  -- the words a panel shows instead of its HP
  set = 166, notEntered = 167, banned = 168,
  able = 175, unable = 176, learned = 177,
}

-- FIRST..SIXTH, in pick order.  The cartridge does NOT write "- 1 -" the way
-- the Gen 3 screen does; it has a word for each place, and the six are
-- consecutive, which is why this is a run and not six named keys.
Gen4Menus.PARTY_ORDER_FIRST = 169
Gen4Menus.PARTY_ORDER_WORDS = 6

-- ---------------------------------------------------------------------------
-- The bag
-- ---------------------------------------------------------------------------

-- EIGHT POCKETS, and the bank that names them.  Bank 395 is the plain list --
-- ITEMS, MEDICINE, POKé BALLS, TMs & HMs, BERRIES, MAIL, BATTLE ITEMS, KEY
-- ITEMS -- in exactly the order an item record's `fieldPocket` numbers them,
-- so the bank index IS the pocket number and no table is needed to pair them.
--
-- Bank 396 is the same eight with a colour code and a pocket glyph in front;
-- that is the bottom screen's tab strip, which this port has no second screen
-- for yet.
Gen4Menus.BAG_BANK = 395
Gen4Menus.BAG_TAB_BANK = 396
Gen4Menus.BAG_POCKETS = 8

-- THE POCKET ICONS ARE SIXTEEN CELLS IN ONE ROW, not thirty-two in a square,
-- and the earlier reading here is worth keeping as a warning.  It said the
-- sheet was four by four on a sixteen-pixel grid, with the top eight cells
-- carrying 160 opaque pixels and the bottom eight 40 -- "the icons and the
-- small markers".  Every one of those numbers was true of the file and none
-- of them was true of the cartridge: the file had been laid out eight tiles
-- wide instead of thirty-two (see `tilesWideFor` in Gen4Screens), so the
-- measurement could only ever agree with whatever the mislaid file held.
--
-- What settles it is the cartridge stating the shape outright.
-- `BagUI_DrawPocketSelectorIcons` blits out of a bitmap `32 * POCKET_MAX`
-- wide by 16 tall, taking a 10x10 corner at `pocketType * 32` -- or at
-- `+ 16` for the pocket that is open.  So: one row, two variants per pocket,
-- sixteen pixels apart, ten of which are drawn.
Gen4Menus.BAG_ICON = 10
Gen4Menus.BAG_ICON_CELL = 16
Gen4Menus.BAG_ICON_STRIDE = 32

-- Where the cartridge's own bag screen puts things, measured off
-- `bag/bag_ui_main` at its own 256x192.
--
-- THE POCKET STRIP AND THE POCKET NAME ARE NOT IN HERE, and that is not an
-- omission.  Both are arithmetic the cartridge does at runtime over the
-- number of pockets the bag was opened with -- eight in the field, five in
-- battle -- so a cached constant cannot express either and would go stale the
-- moment a bag opened with fewer.  `Gen4BagMenu` does the same arithmetic.
Gen4Menus.BAG_LAYOUT = {
  list = { x = 108, y = 8, w = 142, h = 122 },
  description = { x = 40, y = 146 },
  itemIcon = { x = 3, y = 150 },
}

-- ---------------------------------------------------------------------------
-- The summary pages
-- ---------------------------------------------------------------------------

-- BANK 455 IS THE WHOLE SCREEN'S VOCABULARY, and finding it took a scan for
-- the one phrase nothing else in the cartridge says: "To Next Lv." occurs
-- exactly once in all 1,127 banks.  Around it sit the six page titles, every
-- field label, the twenty-five nature lines and the twenty-five characteristic
-- lines -- 187 strings that are this screen and nothing else.
--
-- Two banks looked like this one and are not: 326 and 336 both carry "Exp.
-- Points", "Nature" and "Item", and both are DEBUG menus -- "Random value",
-- "HP rnd", "Set Ribbons", "msg location".  A label list matching on three
-- common words is not an identification; a phrase that occurs once is.
Gen4Menus.SUMMARY_BANK = 455

Gen4Menus.SUMMARY_TEXT = {
  -- page titles
  info = 7, skills = 109, condition = 126, battleMoves = 128,
  contestMoves = 157, ribbons = 179,
  -- the INFO page
  dexNo = 8, name = 10, types = 12, ot = 13, idNo = 15,
  expPoints = 17, toNextLv = 19,
  item = 4, none = 6, male = 1, female = 2, unknown = 22,
  -- the SKILLS page
  hp = 110, attack = 111, defense = 112, spAtk = 113, spDef = 114,
  speed = 115, ability = 116, slash = 117,
  -- the MOVES page
  pp = 135, cancel = 146, power = 147, accuracy = 148, category = 149,
  switch = 152, dashes = 153, dashesLong = 154,
  -- the MEMO page
  memo = 23, sheen = 127, ribbonCount = 182,
}

-- Twenty-five natures and thirty characteristics (five per stat), in the
-- cartridge's order. The HP group starts at 71, before Attack at 76.
Gen4Menus.SUMMARY_NATURE_FIRST = 24
Gen4Menus.SUMMARY_CHARACTERISTIC_FIRST = 71
Gen4Menus.SUMMARY_NATURES = 25
Gen4Menus.SUMMARY_CHARACTERISTICS = 30

-- WHERE THE ROWS ARE, measured off the pages themselves rather than guessed.
-- Each page is a panel of stripes, and a stripe boundary is a row: on
-- `page_info` the colour changes at y = 40, 56, 72, 88, 104, 120, 136, 152 and
-- 168 -- a sixteen-pixel pitch, seven rows of label and value; on
-- `page_skills` the same pitch from 56; and on `page_battle_moves` the changes
-- come at 50, 82, 114 and 146, a pitch of thirty-two, which is the four move
-- rows.  The white value boxes sit at x = 180, which is where the values go.
--
-- WHERE THE PICTURE GOES, and unlike the rows above it is stated TWICE.
--
--   STATED.  PokemonSummaryScreen_LoadMonSprite creates the Pokemon's sprite
--   at (52, 104), and those are not a corner:
--   PokemonSpriteManager_CreateSpriteAtIndex assigns its x and y straight to
--   `transforms.xCenter` and `transforms.yCenter`.  The egg-hatch cutscene
--   settles what that means -- it creates its sprite at
--   (HW_LCD_WIDTH / 2, HW_LCD_HEIGHT / 2 + offset), which is only the middle
--   of the screen if the pair is the CENTRE.
--
--   MEASURED.  Every one of the ten page tilemaps in pl_pst_gra carries the
--   same backing plate in the left column: x 20..83, y 72..135, which is 64
--   square, identical on all ten.  Its centre is (51.5, 103.5) -- exactly the
--   rect a 64-pixel square centred on (52, 104) occupies, because an
--   even-sided rect straddles its centre rather than sitting on it.
--
-- The old value here was the plate's TOP-LEFT CORNER with a two-pixel error in
-- y, which nothing noticed because nothing had ever drawn into the slot.
-- `plate` is carried so a screen can tell the two shapes apart.
--
-- THE PICTURE IS 80 SQUARE AND THE PLATE IS 64, so a Pokemon overhangs its
-- plate by eight pixels on every side.  That is the cartridge's look and not a
-- sizing mistake: shrunk to the plate it would be a different screen.
Gen4Menus.SUMMARY_LAYOUT = {
  label = { x = 112 },
  value = { x = 180 },
  name = { x = 24, y = 24 },
  picture = { x = 52, y = 104, plate = 64 },
  info = { first = 40, pitch = 16, rows = 7 },
  skills = { first = 40, pitch = 16, rows = 6, ability = 144, abilityText = 162 },
  moves = { first = 32, pitch = 32, rows = 4 },
}

-- The pages this port draws, in the order the cartridge tabs through them.
-- Contest moves still need their native page behavior.
Gen4Menus.SUMMARY_PAGES = {
  { key = "info", title = "info", art = "summary/page_info" },
  { key = "memo", title = "memo", art = "summary/page_memo" },
  { key = "skills", title = "skills", art = "summary/page_skills" },
  { key = "moves", title = "battleMoves", art = "summary/page_battle_moves" },
  { key = "condition", title = "condition", art = "summary/page_condition" },
  { key = "ribbons", title = "ribbons", art = "summary/page_ribbons" },
  { key = "exit", art = "summary/page_exit" },
}

-- ---------------------------------------------------------------------------
-- The Poketch
-- ---------------------------------------------------------------------------

-- TWENTY-FIVE APPS, AND TWO BANKS THAT KNOW DIFFERENT THINGS ABOUT THEM.
--
-- Bank 29 entries 11..35 are the app descriptions the Pokétch Company's
-- receptionist reads out, and they are in the cartridge's own APP ORDER --
-- Digital Watch, Analog Watch, Alarm Clock, Stopwatch, Kitchen Timer, ... --
-- which is what an app id means.  What they do not do is say where an app's
-- name ends: "The Digital Watch displays the current time" is one sentence.
--
-- Bank 213 entries 83..107 are the same twenty-five descriptions written for
-- the underground shop, and there each NAME is wrapped in a colour code:
-- "The {COLOR 2}Digital Watch{COLOR 0} app displays...".  So the names come
-- from 213 and the order comes from 29, and pairing them is a real check
-- rather than a formality: every one of the twenty-five coloured names must
-- match the start of exactly one bank-29 description.  They do.
--
-- 213 IS IN A DIFFERENT ORDER (Calculator second, Memo Pad third), which is
-- why the pairing is by text.  Taking the two banks in step would file every
-- app's description under the wrong name from the second one on.
Gen4Menus.POKETCH_DESC_BANK = 29
Gen4Menus.POKETCH_DESC_FIRST = 11
Gen4Menus.POKETCH_NAME_BANK = 213
Gen4Menus.POKETCH_NAME_FIRST = 83
Gen4Menus.POKETCH_COUNT = 25

-- The coloured span of a bank-213 description, which is the app's own name.
function Gen4Menus.poketchName(text)
  if type(text) ~= "string" then return nil end
  return text:match("{COLOR %d+}(.-){COLOR %d+}")
end

-- Which picture each app wears.  Twenty-two of the twenty-five have a face of
-- their own in `/graphic/poketch.narc`; the Friendship Checker, the Pokémon
-- History and the Dot Artist do not, and they fall back to the cartridge's own
-- `unavailable` screen rather than to a blank one this port drew.
Gen4Menus.POKETCH_ART = {
  ["Digital Watch"] = "poketch/digital_watch",
  ["Analog Watch"] = "poketch/analog_watch",
  ["Alarm Clock"] = "poketch/alarm_clock",
  ["Stopwatch"] = "poketch/stopwatch",
  ["Kitchen Timer"] = "poketch/kitchen_timer",
  ["Calendar"] = "poketch/calendar",
  ["Calculator"] = "poketch/calculator",
  ["Pokémon List"] = "poketch/party_status",
  ["Day-Care Checker"] = "poketch/daycare_checker",
  ["Matchup Checker"] = "poketch/matchup_checker",
  ["Berry Searcher"] = "poketch/berry_searcher",
  ["Memo Pad"] = "poketch/memo_pad",
  ["Color Changer"] = "poketch/color_changer",
  ["Marking Map"] = "poketch/marking_map",
  ["Roulette"] = "poketch/roulette",
  ["Coin Toss"] = "poketch/coin_toss",
  ["Pedometer"] = "poketch/pedometer",
  ["Dowsing Machine"] = "poketch/dowsing_machine",
  ["Counter"] = "poketch/counter",
  ["Trainer Counter"] = "poketch/trainer_counter",
  ["Link Searcher"] = "poketch/link_searcher",
  ["Move Tester"] = "poketch/move_tester",
}

Gen4Menus.POKETCH_BORDER = "poketch/poketch_border"
Gen4Menus.POKETCH_UNAVAILABLE = "poketch/unavailable"
Gen4Menus.POKETCH_DIGITS = "poketch/digital_watch_digits"

-- Which apps this port DOES something with, as opposed to drawing.  An app
-- that is not here still appears and still shows its own face; it simply has
-- no behaviour yet, which is visible on screen rather than hidden.
Gen4Menus.POKETCH_LIVE = {
  ["Digital Watch"] = true, ["Analog Watch"] = true, ["Calendar"] = true,
  ["Counter"] = true, ["Coin Toss"] = true, ["Pedometer"] = true,
  ["Pokémon List"] = true,
  ["Calculator"] = true, ["Stopwatch"] = true, ["Kitchen Timer"] = true,
  ["Memo Pad"] = true, ["Dot Artist"] = true, ["Marking Map"] = true,
  ["Roulette"] = true, ["Friendship Checker"] = true,
  ["Day-Care Checker"] = true,
  ["Alarm Clock"] = true, ["Dowsing Machine"] = true,
  ["Move Tester"] = true,
  ["Color Changer"] = true,
  ["Matchup Checker"] = true, ["Pokémon History"] = true,
  ["Berry Searcher"] = true,
}

return Gen4Menus
