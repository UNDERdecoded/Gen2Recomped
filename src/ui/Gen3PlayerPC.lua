-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- EMERALD'S PC.
--
-- The PC in the room the game starts in is a script -- `special 217 /
-- "{PLAYER} booted up the PC." / special 252 BedroomPC / waitstate` -- and
-- 252 opened the GAME BOY screen, because nothing was registered under
-- `PlayerPC` for Hoenn.  Reported from play: "the pc in the starting bedroom
-- ... I get the gen1 menus for depositing items".
--
-- The words and the ORDER are the cartridge's, read by
-- RomExtractorGen3:extractPCMenu out of Emerald's own three menu tables:
--
--     ITEM STORAGE / MAILBOX / DECORATION / TURN OFF
--       ITEM STORAGE -> WITHDRAW ITEM / DEPOSIT ITEM / TOSS ITEM / CANCEL
--       MAILBOX      -> READ / MOVE TO BAG / GIVE / CANCEL
--
-- Note that WITHDRAW comes FIRST here.  Gen 1's screen puts it after nothing
-- at all -- its rows are WITHDRAW / DEPOSIT / TOSS / LOG OFF -- but the two
-- happen to agree on that one; what they do not agree on is the menu ABOVE
-- it, which Gen 1 does not have.
--
-- WHAT WORKS AND WHAT DOES NOT.  Item storage is the same store, the same
-- rules and the same three flows the older screen already implements -- what
-- differed between the cartridges was the furniture, not what withdrawing an
-- item does, so those are reused rather than rewritten.  MAILBOX and
-- DECORATION are the cartridge's rows and are shown as the cartridge shows
-- them, but this port has neither mail nor secret-base decorations yet, so
-- choosing one says so rather than doing nothing: an empty mailbox is a
-- state the cartridge has too, and it is the honest answer here.

local Menu = require("src.ui.Menu")
local Strings = require("src.core.Strings")

local Gen3PlayerPC = {}

local function record(game)
  local c = game and game.data and game.data.constants
  local r = c and c.gen3PCMenu
  return type(r) == "table" and r or nil
end

-- A row's label, from the dataset where there is one.  A cache imported
-- before extractPCMenu existed keeps the same rows in the same order under
-- names this file spells itself, so the screen never comes up blank.
local FALLBACK = {
  main = { "ITEM STORAGE", "MAILBOX", "DECORATION", "TURN OFF" },
  itemStorage = { "WITHDRAW ITEM", "DEPOSIT ITEM", "TOSS ITEM", "CANCEL" },
  mailbox = { "READ", "MOVE TO BAG", "GIVE", "CANCEL" },
}

function Gen3PlayerPC.words(game, menu)
  local r = record(game)
  local list = (r and r[menu]) or FALLBACK[menu]
  return list or {}
end

-- ITEM STORAGE, in the cartridge's order.  The three flows are the older
-- screen's -- see PlayerPC.withdraw and friends.
local function itemStorage(game, onCancel)
  local words = Gen3PlayerPC.words(game, "itemStorage")
  local PC = require("src.ui.PlayerPC")
  game.save.pcItems = game.save.pcItems or {}
  local flows = { PC.withdraw, PC.deposit, PC.toss }
  local rows = {}
  for i, label in ipairs(words) do
    local flow = flows[i]
    rows[#rows + 1] = {
      label = Strings(label),
      keepOpen = flow ~= nil,
      onSelect = flow and function() flow(game) end or nil,
    }
  end
  game.stack:push(Menu.new(game, rows, { noSound = true,
                                         onCancel = onCancel }))
end

-- DECORATION -- the same screen the secret base's PC opens.
--
-- Reported from play: "the lady in the game corner that is supposed to give
-- you a doll doesnt give you anything".  She does: a thousand coins buy a
-- DOLL and it lands in the decoration inventory, and her line is "we'll send
-- it to your PC at home".  This row said the feature was not built, so home
-- was where the doll went to disappear.  The screen behind it -- DECORATE,
-- PUT AWAY, TOSS -- has existed since the secret bases went in; only this
-- door onto it was missing.
local function decoration(game, back)
  local okC, Gen3Commands = pcall(require, "src.script.Gen3Commands")
  local okD, Decor = pcall(require, "src.world.Gen3Decorations")
  -- ASKED BEFORE ANYTHING IS PUSHED.  A cache imported before the decoration
  -- tables were read has no menu to show, and finding that out halfway
  -- through would leave the player looking at a screen that had already
  -- decided to go back.
  local rows = okD and (Decor.record(game and game.data) or {}).menu
  if not (okC and Gen3Commands.decorationPC and type(rows) == "table"
          and #rows > 0) then
    return false
  end
  Gen3Commands.decorationPC(
    { game = game, save = game.save, overworld = game.overworld }, back)
  return true
end

local function notBuilt(game, what)
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game,
    Strings("%s is not in this\nport yet.", what)))
end

-- `onDone` is what the script's `waitstate` is waiting for: Gen3Commands'
-- pushBlocking parks the runner until this screen closes.  Every way out of
-- here goes through `close`, so the park can never outlive the screen.
-- WHICH OF THE FOUR ROWS THIS PC SHOWS.
--
-- The bedroom's shows all four; the one in a Poke Centre leaves DECORATION
-- out and shows three.  That is not this screen's choice -- both specials
-- load a list of row numbers, and the import reads both (pcMenuOrders).  A
-- dataset without them shows everything, which is what this screen did
-- before either was read.
function Gen3PlayerPC.order(game, which, count)
  local r = record(game)
  local list = which and r and r.orders and r.orders[which]
  if type(list) == "table" and #list > 0 then return list end
  local all = {}
  for i = 1, count do all[i] = i end
  return all
end

-- ...and the way back onto this screen once one of its rows is finished with.
-- The decoration menu pushes its own stack of menus and pops them itself, so
-- what it returns to has to be a FRESH PC menu rather than the one it
-- replaced -- which is exactly what the cartridge does: every one of the PC's
-- rows ends by walking back into the PC script.
function Gen3PlayerPC.reopen(game, opts)
  local ok, menu = pcall(Gen3PlayerPC.new, game, opts)
  if ok and menu then pcall(game.stack.push, game.stack, menu) end
end

function Gen3PlayerPC.new(game, opts)
  opts = opts or {}
  game.save.pcItems = game.save.pcItems or {}
  local words = Gen3PlayerPC.words(game, "main")
  local menu
  local function close()
    local done = opts.onDone
    opts.onDone = nil
    if done then done() end
  end
  local rows = {}
  for _, i in ipairs(Gen3PlayerPC.order(game, opts.order, #words)) do
    local label = words[i]
    local row = { label = Strings(label or "") }
    if i == 1 then
      row.keepOpen = true
      row.onSelect = function() itemStorage(game) end
    elseif i == 3 then
      -- DECORATION opens its own screen, and that screen owns what happens
      -- next -- so this row does NOT keepOpen: the decoration menu walks back
      -- into this one itself when the player is done with it.
      row.onSelect = function()
        if not decoration(game, function() Gen3PlayerPC.reopen(game, opts) end) then
          notBuilt(game, Strings(label))
        end
      end
    elseif i == 2 then
      row.keepOpen = true
      row.onSelect = function() notBuilt(game, Strings(label)) end
    else
      -- TURN OFF: the row that ends the session
      row.onSelect = close
    end
    rows[#rows + 1] = row
  end
  menu = Menu.new(game, rows, {
    -- PlayersPCMenu holds BIT_NO_MENU_BUTTON_SOUND on both cartridges
    noSound = true,
    onCancel = close,
  })
  return menu
end

return Gen3PlayerPC
