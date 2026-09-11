-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE MENU ABOVE THE BOXES.
--
-- Reported from play: "for the storage missing deposit, withdrawal, and move
-- pokemon options".  They were missing because this whole screen was -- the
-- port opened the grid outright, so DEPOSIT was hidden on SELECT, WITHDRAW
-- was buried in a per-slot submenu and MOVE POKEMON did not exist at all.
--
-- Emerald asks first.  sPokemonStorageActions is five { label, description }
-- pairs and the cartridge shows them under "What would you like to do?":
--
--     WITHDRAW POKeMON  Move POKeMON stored in BOXES to your party.
--     DEPOSIT POKeMON   Store POKeMON in your party in BOXES.
--     MOVE POKeMON      Organize the POKeMON in BOXES and in your party.
--     MOVE ITEMS        Move items held by any POKeMON in a BOX or your party.
--     SEE YA!           (the way out)
--
-- All five, their descriptions and the prompt are read by
-- RomExtractorGen3:extractPCMenu -- the descriptions are what tell the rows
-- apart, so the order is the cartridge's rather than this file's.
--
-- WHAT EACH ONE DOES HERE.  WITHDRAW, DEPOSIT and MOVE all open the box grid;
-- what differs is what the grid does with a pick, which it takes as a mode.
-- MOVE ITEMS needs held items in boxes, which this port does not carry yet,
-- and says so rather than opening a grid that cannot do it.

local Menu = require("src.ui.Menu")
local Strings = require("src.core.Strings")

local Gen3StorageMenu = {}

local FALLBACK = {
  rows = { "WITHDRAW POKéMON", "DEPOSIT POKéMON", "MOVE POKéMON",
           "MOVE ITEMS", "SEE YA!" },
  prompt = "What would you like to do?",
}

function Gen3StorageMenu.record(game)
  local c = game and game.data and game.data.constants
  local pc = c and c.gen3PCMenu
  local box = pc and pc.storage
  if type(box) == "table" and type(box.rows) == "table" and #box.rows > 0 then
    return box
  end
  return FALLBACK
end

-- The three that open the grid, in the cartridge's own order.
local MODES = { "withdraw", "deposit", "move" }

-- `onDone` is what a SCRIPT is waiting for and `onCancel` is what a caller
-- inside the engine passes; this screen is opened both ways -- the Poke
-- Centre's "SOMEONE'S PC" is special 63, and the bedroom PC's box row is a
-- plain push -- so every way out has to answer both, exactly once.
--
-- Reported from play: "when selecting someones pc in the pc for box storage
-- it loops and asks over and over again which box should be accessed".  That
-- was the OTHER half of the same mistake -- the alias did not serve a push
-- carrying `onDone`, so no screen opened at all and the script asked its
-- question again -- and a screen that took the option and then never called
-- it back would have parked the script instead.
function Gen3StorageMenu.new(game, opts)
  opts = opts or {}
  local record = Gen3StorageMenu.record(game)
  local Screens = require("src.ui.Screens")
  local rows = {}
  local closed = false
  local function close()
    if closed then return end
    closed = true
    if opts.onCancel then opts.onCancel() end
    if opts.onDone then opts.onDone() end
  end
  for i, label in ipairs(record.rows) do
    local mode = MODES[i]
    local row = { label = Strings(label),
                  describe = (record.describe or {})[i] }
    if mode then
      row.keepOpen = true
      row.onSelect = function()
        Screens.push(game, "BoxMenu", { mode = mode })
      end
    elseif i < #record.rows then
      -- MOVE ITEMS: the cartridge's row, and an honest answer under it
      row.keepOpen = true
      row.onSelect = function()
        local TextBox = require("src.render.TextBox")
        game.stack:push(TextBox.new(game,
          Strings("%s is not in this\nport yet.", Strings(label))))
      end
    else
      -- SEE YA!
      row.onSelect = close
    end
    rows[#rows + 1] = row
  end
  return Menu.new(game, rows, {
    noSound = true,
    onCancel = close,
  })
end

return Gen3StorageMenu
