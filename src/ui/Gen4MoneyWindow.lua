-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE MONEY WINDOW, WHICH IS WHAT 109 SCRIPT ROWS WERE ASKING FOR.
--
-- `showmoney`, `hidemoney` and `updatemoneydisplay` lowered onto `g4_noop`
-- with the subjects "money box" and "the money window refresh", and the census
-- that found the door sounds puts them second: **109 invocations** over the
-- decoded corpus, behind doors (194) and ahead of the journal (78).
--
-- It is not the shop's money display. `ShopMenu` already shows a balance
-- inside a shop; this is the standalone window a FIELD script puts up while
-- you decide -- the Game Corner's coin counter, the Day-Care's fee, the
-- Ribbon Syndicate, the Floaroma flower seller, the Pastoria gates, the cafe.
-- A script that takes money and shows you what you have.
--
-- WHAT THE CARTRIDGE DOES, in three calls:
--
--     ScrCmd_ShowMoney           -> FieldMenu_CreateMoneyWindow(fs, l, t)
--     ScrCmd_UpdateMoneyDisplay  -> FieldMenu_PrintMoneyToWindow(fs, w)
--     ScrCmd_HideMoney           -> FieldMenu_DeleteMoneyWindow(w)
local Gen4MoneyWindow = {}

-- `MONEY_WINDOW_WIDTH` / `_HEIGHT` in src/overlay005/field_menu.c.
Gen4MoneyWindow.WIDTH_TILES = 10
Gen4MoneyWindow.HEIGHT_TILES = 4

-- `GLYPH_ROW_HEIGHT` in the same file: the label prints at the window's own
-- (0, 0) and the amount one glyph row down.  Sixteen is also the pitch
-- `drawGen4SaveInfo` and `TextBox` use, because it is the DS system font's
-- max letter height plus its line spacing.
Gen4MoneyWindow.ROW_PITCH = 16

-- `TEXT_BANK_UNK_0543` is line 544 of generated/text_banks.txt, so bank 543 --
-- the same line-minus-one rule as every other bank in this port.  Entry 18 is
-- the label and entry 19 is the amount's format string.
Gen4MoneyWindow.BANK = 543
Gen4MoneyWindow.LABEL_ENTRY = 18
Gen4MoneyWindow.AMOUNT_ENTRY = 19

-- `StringTemplate_SetNumber(template, 0, money, 6, PADDING_MODE_SPACES,
-- CHARSET_MODE_EN)` -- six digits, padded with SPACES rather than zeros, into
-- string slot 0.
Gen4MoneyWindow.DIGITS = 6

-- THE POUND SIGN COMES FROM THE CARTRIDGE'S OWN STRING, which is the whole
-- reason this reads bank 543 instead of formatting a number itself.
--
-- Entry 19 is `"${STRVAR_1 55 0 0}"` -- a literal ASCII `$`, because the DS
-- English font draws that character as the Poke-dollar.  `Gen4TrainerCard`
-- works that out the hard way and keeps a `MONEY_SIGN = "$"` local with a
-- paragraph explaining it; resolving the cartridge's format string brings the
-- sign along for free and there is no second spelling of it here to drift.
--
-- `left` and `top` ARE IN THAT ORDER, and the middle of pret is confusing
-- about it on purpose-looking grounds:
--
--     ScrCmd_ShowMoney:  tilemapLeft = GetVar; tilemapTop = GetVar;
--                        FieldMenu_CreateMoneyWindow(fs, tilemapLeft, tilemapTop)
--     FieldMenu_CreateMoneyWindow(FieldSystem *fs, u8 tilemapTop, u8 tilemapLeft)
--                        Window_Add(..., tilemapTop, tilemapLeft, ...)
--     Window_Add(..., u8 tilemapLeft, u8 tilemapTop, ...)
--
-- The parameter names are swapped twice, so they cancel: **operand one is the
-- LEFT and operand two is the TOP**.  Every call site in the cartridge agrees
-- -- `ShowMoney 20, 2` almost everywhere and `ShowMoney 20, 7` in the Game
-- Corner -- which puts a 10-tile window at x 160..240 of a 256-pixel screen,
-- the top right corner.  Reading it the other way round would put it off the
-- bottom of the screen, which is the kind of wrong that looks like a bug in
-- the frame drawing.
function Gen4MoneyWindow.panelFor(game, left, top)
  local save = game and game.save
  if type(save) ~= "table" then return nil end
  local data = game.data
  local Gen4Text = require("src.import.Gen4Text")

  -- six digits, space padded, the way StringTemplate_SetNumber does it
  local money = math.floor(tonumber(save.money) or 0)
  if money < 0 then money = 0 end
  local digits = tostring(money)
  local amount = (" "):rep(math.max(0, Gen4MoneyWindow.DIGITS - #digits)) .. digits

  Gen4Text.buffer(game, amount)
  local label = Gen4Text.resolve(data, Gen4MoneyWindow.BANK,
                                 Gen4MoneyWindow.LABEL_ENTRY, game)
  local value = Gen4Text.resolve(data, Gen4MoneyWindow.BANK,
                                 Gen4MoneyWindow.AMOUNT_ENTRY, game)
  -- NO ENGLISH FALLBACK FOR THE LABEL, for the reason
  -- `Gen4UndergroundMenu:labelFor` gives: a missing bank entry is a broken
  -- import, and a hardcoded word hides it behind something that looks right.
  -- The AMOUNT is different -- a window with no number in it is worse than one
  -- with the wrong sign -- so that one falls back to the digits alone.
  if type(value) ~= "string" or value == "" then value = amount end
  return {
    left = math.floor(tonumber(left) or 20),
    top = math.floor(tonumber(top) or 2),
    label = (type(label) == "string" and label ~= "") and label or nil,
    amount = value,
    tilesW = Gen4MoneyWindow.WIDTH_TILES,
    tilesH = Gen4MoneyWindow.HEIGHT_TILES,
  }
end

-- Drawn the way the save panel and FireRed's lift window are: the frame one
-- tile out and two tiles bigger than the window the cartridge measures, the
-- content at the window's own origin.
--
-- The amount is RIGHT-ALIGNED to the window's right edge, which is the
-- cartridge's own `printerOffset = (WIDTH * 8) - Font_CalcStringWidth(...)`.
-- That is also why the number is space-padded rather than zero-padded: the
-- padding is inside a right-aligned string, so it only shows up as the
-- consistent column the cartridge wants.
function Gen4MoneyWindow.draw(panel)
  if type(panel) ~= "table" then return false end
  local Font = require("src.render.Font")
  local tw = panel.tilesW or Gen4MoneyWindow.WIDTH_TILES
  local th = panel.tilesH or Gen4MoneyWindow.HEIGHT_TILES
  local left, top = panel.left or 20, panel.top or 2
  Font.drawBox(left - 1, top - 1, tw + 2, th + 2)
  local x = left * 8
  local y = top * 8
  local right = x + tw * 8
  love.graphics.setColor(0, 0, 0, 1)
  if panel.label then Font.draw(panel.label, x, y) end
  local amount = panel.amount
  if amount and amount ~= "" then
    Font.draw(amount, right - Font.width(amount), y + Gen4MoneyWindow.ROW_PITCH)
  end
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

-- THE COIN WINDOW (FieldMenu_DrawCoinWindow / FieldMenu_PrintCoinsToWindow):
-- COIN_BP_WINDOW_WIDTH x HEIGHT, 10 x 2 tiles, one line -- bank 361
-- (TEXT_BANK_MENU_ENTRIES) entry 197, "{STRVAR_1 54 0 0} Coins", with the
-- count in five space-padded digits, right-aligned like the money.
Gen4MoneyWindow.COIN_BANK = 361
Gen4MoneyWindow.COIN_ENTRY = 197
Gen4MoneyWindow.COIN_DIGITS = 5

function Gen4MoneyWindow.coinPanelFor(game, left, top)
  local save = game and game.save
  if type(save) ~= "table" then return nil end
  local coins = require("src.import.Gen4GameCorner").coins(save)
  local digits = tostring(coins)
  local amount = (" "):rep(math.max(0, Gen4MoneyWindow.COIN_DIGITS - #digits)) .. digits
  local saved = game.stringBuffers and game.stringBuffers[1]
  require("src.import.Gen4Text").buffer(game, amount)
  local line = require("src.import.Gen4Text").resolve(game.data, Gen4MoneyWindow.COIN_BANK,
                                                       Gen4MoneyWindow.COIN_ENTRY, game)
  -- the window must not eat the script's own buffer 0
  if game.stringBuffers then game.stringBuffers[1] = saved end
  if type(line) ~= "string" or line == "" then line = amount end
  return {
    left = math.floor(tonumber(left) or 20),
    top = math.floor(tonumber(top) or 2),
    amount = line,
    coins = true,
    tilesW = 10,
    tilesH = 2,
  }
end

function Gen4MoneyWindow.drawCoins(panel)
  if type(panel) ~= "table" then return false end
  local Font = require("src.render.Font")
  local left, top = panel.left or 20, panel.top or 2
  Font.drawBox(left - 1, top - 1, panel.tilesW + 2, panel.tilesH + 2)
  local right = (left + panel.tilesW) * 8
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(panel.amount, right - Font.width(panel.amount), top * 8)
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

return Gen4MoneyWindow
