-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Emerald's START menu.
--
-- Not the Gen 2 one with different words. That menu is a Game Boy list in a
-- 20-tile-wide letterbox whose rows are POKéDEX / POKéGEAR / POKéMON / ITEM;
-- this one is a 240-wide GBA screen whose rows come off the cartridge, and
-- whose fourth entry is a device Johto does not have.
--
-- WHERE THE ROWS COME FROM.
--
-- Nothing on the cartridge declares the menu's contents: sStartMenuItems is
-- an array of {label, handler} pairs and only the label half is data. But the
-- labels sit CONSECUTIVELY in the text region in the order the menu draws
-- them, so that run is the layout -- and it is the run the discovery pass
-- pins, by the one thing that separates it from the POKéNAV's own menu of
-- the same first four words: the player's own name between POKéNAV and SAVE.
--
--   POKéDEX  POKéMON  BAG  POKéNAV  <PLAYER>  SAVE  OPTION  EXIT
--
-- So the order is the cartridge's, and so is every word in it. What is NOT
-- derived is the geometry -- the box's corner, its width, the line pitch --
-- which is measured off the screen rather than found in the ROM. Those
-- numbers are together at the top of this file, and they are the part to
-- correct against a screenshot.

local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Screens = require("src.ui.Screens")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3StartMenu = {}
Gen3StartMenu.__index = Gen3StartMenu

local GBA_W, GBA_H = 240, 160

-- RECONSTRUCTED, not derived: the window sits in the top-left corner, and
-- rows are two tiles apart like every other list on this cartridge.
local BOX_TX, BOX_TY = 0, 0
local BOX_TW = 9
local ROW_STEP = 2                    -- tiles between rows
local TEXT_INSET_X = 8
local CURSOR_X = 2

-- HOW FAR DOWN ITS ROW A LINE SITS, which is not a constant either.
--
-- A row is two tiles; an 8-pixel Game Boy glyph wants four pixels of air above
-- it to sit in the middle of one, and Emerald's fifteen-pixel face wants none
-- -- there is only one pixel spare.  A fixed inset written for the first puts
-- the second through the bottom of the box.
local function textInsetY()
  local Font_ = require("src.render.Font")
  return math.max(0, math.floor((ROW_STEP * 8 - Font_.glyphHeight()) / 2))
end

function Gen3StartMenu:uiSize() return GBA_W, GBA_H end
function Gen3StartMenu:wantsFillScale() return true end

-- colour, not four shades: the same reasoning as Gen3Title's
function Gen3StartMenu:sgbPalettes()
  local P = require("src.render.PaletteFX")
  return { P.trueColorZone(0, 0, math.ceil(GBA_W / 8) - 1,
                           math.ceil(GBA_H / 8) - 1) }
end

-- Which rows this save can actually use.
--
-- Emerald hides a row rather than greying it: no dex until Birch hands it
-- over, no POKéMON until something is in the party, no POKéNAV until it is
-- given. The engine's own predicates answer the first two; the third is a
-- Gen 3 flag, and a save that has never set it simply does not get the row.
local function rowEnabled(game, key)
  local save = game.save or {}
  if key == "pokedex" then
    -- THE SAME KEY WAS UNREACHABLE HERE TOO.
    --
    -- The dex is not an item in Gen 3 -- there is no `giveitem` to miss.  It
    -- is a FLAG, and Birch's lab really does set it: 0x1FA3AC plays the
    -- fanfare, prints "{PLAYER} received the POKeDEX!", and runs
    -- `setflag $861`.  BuildStartMenuActions then gates row 0 on that same
    -- $861.
    --
    -- But `Flags.hasPokedex` answers for EVENT_GOT_POKEDEX and
    -- ENGINE_POKEDEX, which are the Game Boy cartridges' names.  A Gen 3
    -- save spells its flags FLAG_G3_%04X -- what the script VM writes and
    -- what a converted save round-trips -- so the row could never appear,
    -- however far into the game you got.  Exactly the POKeNAV's bug, eleven
    -- lines below, in a different disguise.
    --
    -- The Gen 1/2 predicate is kept as the fallback: it is still the right
    -- answer for a dataset that spells it that way.
    local record = (game.data.constants or {}).gen3StartMenu
    local key3 = (record and record.pokedexFlag) or "FLAG_G3_0861"
    if (save.flags or {})[key3] == true then return true end
    local ok, Flags = pcall(require, "src.script.Flags")
    return ok and Flags.hasPokedex(save) or false
  elseif key == "pokemon" then
    return #(save.party or {}) > 0
  elseif key == "pokenav" then
    -- THE KEY WAS UNREACHABLE.  Gen 3 flags are spelled FLAG_G3_%04X here --
    -- that is what the script VM writes and what a converted save round-trips
    -- -- so a name borrowed from pokeemerald's header could never be true and
    -- the row could never appear, whatever the player had been given.
    --
    -- The number is the cartridge's: BuildStartMenuActions adds the POKeNAV
    -- row only when flag $862 is set, between the BAG row and the PLAYER row,
    -- which is exactly where it sits in the list below.
    local record = (game.data.constants or {}).gen3StartMenu
    local key3 = (record and record.pokenavFlag) or "FLAG_G3_0862"
    return (save.flags or {})[key3] == true
  end
  return true
end

-- The eight rows, paired with what each one opens. The ORDER is the
-- cartridge's run; this table only says what each of its labels does.
-- `boot` names the screen for the three rows that have a GBA version, so a
-- Gen 3 cache opens Emerald's bag / party / card and a Gen 1 or 2 one still
-- opens the Game Boy screens from the same table.
local ACTIONS = {
  { key = "pokedex", screen = "PokedexMenu" },
  { key = "pokemon", boot = "party", screen = "PartyMenu" },
  { key = "bag", boot = "bag", screen = "BagMenu" },
  { key = "pokenav", screen = "Gen3Pokenav" },
  { key = "player", boot = "trainerCard", screen = "TrainerCard" },
  { key = "save", screen = nil },        -- handled below
  { key = "option", screen = nil },      -- the dataset names it; see below
  { key = "exit", screen = nil },
}

function Gen3StartMenu.new(game)
  local self = setmetatable({}, Gen3StartMenu)
  self.game = game
  self.index = 1
  self.blink = 0

  local record = (game.data.constants or {}).gen3StartMenu
  local labels = record and record.items
  if not labels then
    Logger.warn("gen3 start menu: this dataset carries no menu labels -- "
                .. "falling back to the engine's own")
    labels = { Strings("POKéDEX"), Strings("POKéMON"), Strings("BAG"),
               "POKéNAV", Strings("PLAYER"), Strings("SAVE"),
               Strings("OPTION"), Strings("EXIT") }
  end

  -- {PLAYER} is a placeholder the cartridge splices the name into, and this
  -- is the one row whose label is not a word.
  local playerName = (game.save and game.save.player and game.save.player.name)
                     or Strings("PLAYER")

  self.rows = {}
  self:buildRows(game, labels, playerName)
  return self
end

-- The eight cartridge rows, plus the one this port adds.
--
-- MODS is not Emerald's and never will be, but it is the only way into the
-- manager once a game is running, and the Game Boy start menu has carried it
-- for as long as the manager has existed.  It appears only when at least one
-- mod is actually installed, so a vanilla game's menu is the cartridge's
-- eight words and nothing else.
function Gen3StartMenu:buildRows(game, labels, playerName)
  for i, action in ipairs(ACTIONS) do
    local label = labels[i]
    if action.key == "player" then label = playerName end
    if label and rowEnabled(game, action.key) then
      local boot = game.data.field and game.data.field.boot
      local named = action.boot and (boot and boot.screens or {})[action.boot]
      self.rows[#self.rows + 1] = { label = label, key = action.key,
                                    screen = named or action.screen }
    end
  end
  -- LINK, which the Game Boy menu has had since link play went in and this
  -- one never got.
  --
  -- Reported from play: "make sure the link features in the start menu for
  -- emerald like it is in gen1 and gen2".  Emerald's own answer to "I want to
  -- trade" is a WARP -- you walk into a POKéMON CENTER, up the stairs, and
  -- talk to the attendant, because a GBA link is a cable between two rooms.
  -- This port's link is a network session, and there is no cable and no
  -- second room; the Game Boy menu solved that years ago with a LINK row and
  -- there is no reason Hoenn should be the one region you cannot reach it
  -- from.  So the row goes in on the same terms as MODS: before EXIT,
  -- clearly not one of the cartridge's eight, and only when it can do
  -- anything -- link play needs a party.
  --
  -- The WORDS on the screens it opens are still the cartridge's; see
  -- extractTradeText and src/link/TradeText.lua.
  local function insertBeforeExit(row)
    local at = #self.rows
    if self.rows[at] and self.rows[at].key == "exit" then
      table.insert(self.rows, at, row)
    else
      self.rows[#self.rows + 1] = row
    end
  end

  if #((game.save or {}).party or {}) > 0 then
    insertBeforeExit({ label = Strings("LINK"), key = "link" })
  end

  local status = game.modStatus
  if status and #(status.available or {}) > 0 then
    insertBeforeExit({ label = Strings("MODS"), key = "mods",
                       screen = "ManagerState" })
  end

  -- QUIT GAME, which is this port's and is NOT the cartridge's.
  --
  -- EXIT is Emerald's word for "close this menu" -- its handler is one call
  -- that tears the window down and hands control back to the field, and a GBA
  -- has nowhere else to go.  That is what EXIT does here, and it works.  But
  -- this port runs on a machine that DOES have somewhere to go, and a player
  -- who picks the row named EXIT and stays in the game is not being told
  -- that; they are being told the button is broken.  So the way out gets its
  -- own row and its own word, below EXIT, in the same spirit as MODS: the
  -- eight rows above it are still the cartridge's eight, in the cartridge's
  -- order, doing the cartridge's things.
  --
  -- `boot.startMenuQuit = false` takes it away again for a dataset that wants
  -- the cartridge's menu and nothing else.
  local boot = game.data.field and game.data.field.boot
  if not (boot and boot.startMenuQuit == false) then
    self.rows[#self.rows + 1] = { label = Strings("QUIT GAME"), key = "quit" }
  end
end

function Gen3StartMenu:reopen()
  Screens.push(self.game, "Gen3StartMenu")
end

-- Pop the menu, and only the menu.
--
-- The save flow's last beat closes the START menu from inside a TextBox
-- callback, and by then this state is no longer guaranteed to be on top.
-- A bare pop() there would take whatever IS on top -- the map, on a bad
-- frame -- so the pop happens only while this state is the top one, and
-- otherwise the state is lifted out of the stack where it sits.
function Gen3StartMenu:close()
  local stack = self.game.stack
  if stack:top() == self then return stack:pop() end
  for i = #stack.states, 1, -1 do
    if stack.states[i] == self then
      table.remove(stack.states, i)
      if self.exit then self:exit() end
      return
    end
  end
end

function Gen3StartMenu:choose(row)
  if not row then return end
  if row.key == "exit" then
    -- EXIT is the cartridge's "close this menu", not "leave the game" -- a
    -- GBA has nowhere to go.  Quitting lives on the main menu's EXIT GAME.
    -- Logged because it has been reported as doing nothing: if this line is
    -- in the log and the menu stayed up, the pop is what failed, not the row.
    Logger.info("gen3 start menu: EXIT -- closing")
    pcall(function()
      require("src.core.Sound").play(self.game.data, "Press_AB")
    end)
    return self:close()
  end
  if row.key == "quit" then
    -- the port's own way out; see buildRows for why it is not EXIT
    Logger.info("gen3 start menu: QUIT GAME")
    pcall(function()
      require("src.core.Sound").play(self.game.data, "Press_AB")
    end)
    if love and love.event and love.event.quit then love.event.quit() end
    return
  end
  if row.key == "link" then
    -- the link screen is a state of its own, not a Screens entry: it owns
    -- the socket and has to outlive the menu that opened it
    Logger.info("gen3 start menu: LINK")
    self:close()
    local ok, LinkState = pcall(require, "src.link.LinkState")
    if not ok then
      Logger.warn("gen3 start menu: link play is not available")
      return
    end
    return self.game.stack:push(LinkState.new(self.game))
  end
  if row.key == "save" then return self:startSave() end
  if row.key == "option" then
    local boot = self.game.data.field and self.game.data.field.boot
    local screens = boot and boot.screens or {}
    self:close()
    return Screens.push(self.game, screens.options or "OptionsMenu",
                        { onCancel = function() self:reopen() end })
  end
  if not row.screen then
    -- a row the port does not serve yet closes rather than doing nothing
    -- visible: a menu that swallows A reads as a broken button
    Logger.info("gen3 start menu: %s is not implemented yet", row.key)
    return self:close()
  end
  self:close()
  local onCancel = function() self:reopen() end
  Screens.push(self.game, row.screen, { onCancel = onCancel })
end

-- THE SAVE FLOW, which is a conversation and not a write.
--
-- Emerald's SAVE row does not save.  It opens the save-info window -- the
-- same PLAYER / BADGES / POKeDEX / TIME panel the Gen 2 menu shows -- and
-- then asks, and only a YES reaches the card (sub_80F79F0 -> the SAVE_*
-- state machine in save.c).  The row used to call SaveData.save inside a
-- pcall and close, which is why choosing it looked like nothing happening:
-- the whole menu vanished for the one frame the write took.
--
-- The beats, in the cartridge's order:
--   1. the info panel,
--   2. "Would you like to save the game?" with a YES/NO the player can
--      back out of (B is NO, and NO returns to the menu, not to the map),
--   3. gText_SavingDontTurnOff -- shown BEFORE the write, because that is
--      the whole point of the message,
--   4. the write, the save jingle, and gText_PlayerSavedGame.
--
-- The menu is closed only at the end, and only on a completed save; a NO
-- leaves it exactly where it was.
-- THE INFO PANEL IS A WINDOW, not a page of dialogue.
--
-- It was four lines pushed through the text box, which is wrong twice over:
-- the cartridge draws it as its own window over the menu, and a text box
-- paginates -- so the four rows arrived as two pages and the player pressed A
-- to see the other half of their own save file.
--
-- THE WORDS are the cartridge's: PLAYER, POKéDEX, TIME and BADGES sit
-- consecutively in the text region, which is the same run the START menu's
-- rows were found in.  THE ORDER IS NOT -- the run is memory order and the
-- screen shows BADGES second -- so the order here is a judgement, stated as
-- one, the same way the OPTION screen's rows are.
local SAVE_PANEL = { tx = 0, ty = 0, tw = 14, th = 10 }
local SAVE_ROW_PITCH = 16
local SAVE_VALUE_X = 80

function Gen3StartMenu:saveInfoRows()
  local game = self.game
  local save = game.save or {}
  local words = ((game.data.constants or {}).gen3Screens or {}).saveInfo
  words = words and words.items or { Strings("PLAYER"), Strings("POKéDEX"),
                                     Strings("TIME"), Strings("BADGES") }
  local name = (save.player and save.player.name) or Strings("PLAYER")
  local badges = 0
  local okBadges, Badges = pcall(require, "src.inventory.Badges")
  if okBadges then
    local ok, count = pcall(Badges.count, game.data, save)
    badges = (ok and tonumber(count)) or 0
  end
  local owned = 0
  for _ in pairs((save.pokedex or {}).owned or {}) do owned = owned + 1 end
  local t = math.floor(tonumber(save.playTime) or 0)
  -- screen order: PLAYER, BADGES, POKéDEX, TIME
  return {
    { words[1] or "PLAYER", name },
    { words[4] or "BADGES", tostring(badges) },
    { words[2] or "POKéDEX", tostring(owned) },
    { words[3] or "TIME",
      ("%d:%02d"):format(math.floor(t / 3600), math.floor(t / 60) % 60) },
  }
end

function Gen3StartMenu:startSave()
  local game = self.game
  local TextBox = require("src.render.TextBox")
  local name = (game.save and game.save.player and game.save.player.name)
               or Strings("PLAYER")
  -- the panel is drawn by THIS state, underneath the question, for as long
  -- as the flow is up
  self.savePanel = true
  local prompt = Strings("Would you like to save\nthe game?")
  game.stack:push(TextBox.new(game, prompt, nil, {
    choice = function(yes)
      if not yes then self.savePanel = false return end
      -- shown before the write, which is what the message is for
      game.stack:push(TextBox.new(game,
        Strings("SAVING...\nDON'T TURN OFF THE POWER."), function()
          local ok, err = pcall(function()
            if game.writeSave then game:writeSave()
            else require("src.core.SaveData").save(game.save) end
          end)
          if not ok then
            Logger.warn("gen3 start menu: save failed (%s)", tostring(err))
            self.savePanel = false
            game.stack:push(TextBox.new(game,
              Strings("Save failed.\nPlease try again.")))
            return
          end
          pcall(function()
            require("src.core.Sound").play(game.data, "Save")
          end)
          game.stack:push(TextBox.new(game,
            Strings("%s saved the game.", name), function()
              self.savePanel = false
              self:close()
            end))
        end))
    end,
  }))
end

function Gen3StartMenu:animate(dt)
  self.blink = (self.blink + 1) % 60
end

function Gen3StartMenu:update(dt)
  self:animate(dt)
  local input = self.game.input
  local n = #self.rows
  if n == 0 then return self:close() end
  if input:wasPressed("down") then
    self.index = self.index % n + 1
  elseif input:wasPressed("up") then
    self.index = (self.index - 2) % n + 1
  elseif input:wasPressed("a") then
    self:choose(self.rows[self.index])
  elseif input:wasPressed("b") or input:wasPressed("start") then
    self:close()
  end
end

function Gen3StartMenu:drawSavePanel(inset)
  Font.drawBox(SAVE_PANEL.tx, SAVE_PANEL.ty, SAVE_PANEL.tw, SAVE_PANEL.th)
  love.graphics.setColor(0, 0, 0, 1)
  local y = (SAVE_PANEL.ty + 1) * 8 + inset
  for _, row in ipairs(self:saveInfoRows()) do
    Font.draw(row[1], (SAVE_PANEL.tx + 1) * 8, y)
    Font.draw(row[2], SAVE_VALUE_X, y)
    y = y + SAVE_ROW_PITCH
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Gen3StartMenu:draw()
  local inset = textInsetY()
  if self.savePanel then return self:drawSavePanel(inset) end
  local th = #self.rows * ROW_STEP + 2
  Font.drawBox(BOX_TX, BOX_TY, BOX_TW, th)
  love.graphics.setColor(0, 0, 0, 1)
  for i, row in ipairs(self.rows) do
    local y = (BOX_TY + 1 + (i - 1) * ROW_STEP) * 8 + inset
    Font.draw(row.label, BOX_TX * 8 + TEXT_INSET_X, y)
    if i == self.index then
      -- Theme.cursor, not a literal arrow: this cartridge has NO arrow in
      -- its font (Emerald draws the menu cursor as a sprite), so the
      -- extractor fills three blank cells with drawn shapes and puts their
      -- codes in font.symbols.  Drawing "\u{25B6}" here asked the charmap for a
      -- character that is not in it, and a code the charmap cannot supply
      -- draws nothing at all -- which is exactly what a menu with no
      -- selection indicator looks like.
      --
      -- It also does not BLINK.  The Gen 2 list cursor blinks; Emerald's
      -- sits still and the selected row is the only thing that moves.
      Font.drawCode(Theme.cursor, BOX_TX * 8 + CURSOR_X, y)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3StartMenu
