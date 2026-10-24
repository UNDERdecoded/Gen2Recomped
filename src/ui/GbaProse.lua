-- Native GBA label bindings. The identifiers follow each reference reader;
-- equal English words do not imply that two dialogs use the same label.
local V = require("src.core.GameVersion")
local P = {}
local FR_ACTION = {
  summary = 0,
  switch = 1,
  cancel = 2,
  item = 3,
  give = 4,
  takeItem = 5,
  takeMail = 5,
  shift = 10,
  sendOut = 11,
  enter = 12,
  noEntry = 13,
  store = 14,
}
local EM_ACTION = {
  summary = "gText_Summary5",
  switch = "gText_Switch2",
  cancel = "gText_Cancel2",
  item = "gText_Item",
  give = "gMenuText_Give",
  takeItem = "gText_Take",
  takeMail = "gText_Take",
  shift = "gText_Shift",
  sendOut = "gText_SendOut",
  enter = "gText_Enter",
  noEntry = "gText_NoEntry",
  store = "gText_Store",
}
local WORD_ROLE = { "shift", "sendOut", "switch", "summary", false, "enter", "noEntry", "takeItem" }
local ITEM_PC = {
  title = "gText_WithdrawItem",
  withdraw = "gText_Withdraw",
  give = "gOtherText_Give",
  cancel = "gFameCheckerText_Cancel",
}
function P.read(game, label, fallback)
  local data = game and game.data
  local overrides = data and data._romTextGeneration == 3 and data.romText
  local value = overrides and label and overrides[label] or nil
  if value == nil then
    return fallback
  end
  return (require("src.render.TextBox").substitute(game, value):gsub("[\f\v]", "\n\n"))
end
function P.partyAction(game, role, fallback)
  local version, label = V.get(), nil
  if version == "firered" then
    local index = FR_ACTION[role]
    if index ~= nil then
      label = "sCursorOptions[" .. index .. "]"
    end
  elseif version == "emerald" then
    label = EM_ACTION[role]
  end
  return P.read(game, label, fallback)
end
function P.partyWord(game, index, fallback)
  return P.partyAction(game, WORD_ROLE[index], fallback)
end
function P.partyCancel(game, fallback)
  local label = V.get() == "firered" and "gFameCheckerText_Cancel"
    or V.get() == "emerald" and "gText_Cancel"
    or nil
  return P.read(game, label, fallback)
end
function P.itemPc(game, role, fallback)
  return P.read(game, V.get() == "firered" and ITEM_PC[role] or nil, fallback)
end
return P
