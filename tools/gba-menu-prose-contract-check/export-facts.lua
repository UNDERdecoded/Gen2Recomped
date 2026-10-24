package.path = "./?.lua;./?/init.lua;" .. package.path
local version = assert(arg[1])
require("src.core.GameVersion").set(version)
local M = require("src.import.gba.versions")
M.select(version)
local wanted = version == "firered"
    and {
      "gFameCheckerText_Cancel",
      "gText_WithdrawItem",
      "gText_Withdraw",
      "gOtherText_Give",
    }
  or {
    "gText_Summary5",
    "gText_Switch2",
    "gText_Cancel2",
    "gText_Item",
    "gMenuText_Give",
    "gText_Take",
    "gText_Take2",
    "gText_Shift",
    "gText_SendOut",
    "gText_Enter",
    "gText_NoEntry",
    "gText_Store",
    "gText_Cancel",
  }
local facts = { text = {}, tables = {} }
for _, name in ipairs(wanted) do
  facts.text[name] = assert(M.NAMED_TEXTS[name], name)
end
if version == "firered" then
  for _, row in pairs(M.TEXT_TABLES) do
    if row.name == "sCursorOptions" then
      facts.tables.sCursorOptions = row
    end
  end
  assert(facts.tables.sCursorOptions)
end
print("GBA_MENU_FACTS " .. require("src.link.Json").encode(facts))
