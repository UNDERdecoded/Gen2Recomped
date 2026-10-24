-- One public consumer on both engines. These are native profile labels,
-- not renderer replacements or English-word substitutions.
local mod = ...
mod.exports.api = mod
if not mod:supports("content", "rom_text") then
  return
end
local mode = mod:read("case.txt") or "all"
local profile = mod:read("profile.txt") or "both"
local labels = {
  { 0, "gText_Summary5", "SUMMARY" },
  { 1, "gText_Switch2", "SWITCH" },
  { 2, "gText_Cancel2", "CANCEL" },
  { 3, "gText_Item", "ITEM" },
  { 4, "gMenuText_Give", "GIVE" },
  { 5, "gText_Take", "TAKE" },
  { 10, "gText_Shift", "SHIFT" },
  { 11, "gText_SendOut", "SEND_OUT" },
  { 12, "gText_Enter", "ENTER" },
  { 13, "gText_NoEntry", "NO_ENTRY" },
  { 14, "gText_Store", "STORE" },
}
local prose = mod.content.rom_text
for _, row in ipairs(labels) do
  if
    mode ~= "cancel-only" and mode ~= "take-only"
    or mode == "cancel-only" and row[3] == "CANCEL"
    or mode == "take-only" and row[3] == "TAKE"
  then
    for _, entry in ipairs({ { "firered", "sCursorOptions[" .. row[1] .. "]" }, { "emerald", row[2] } }) do
      if profile == "both" or profile == entry[1] then
        if mode == "remove" then
          prose:remove(entry[2])
        else
          local value = mode == "empty" and "" or "MOD_" .. row[3]
          if mode == "controls" and row[3] == "SUMMARY" then
            value = "A\nB\fC\vD"
          end
          prose:override(entry[2], value)
        end
      end
    end
  end
end
if mode ~= "cancel-only" and mode ~= "take-only" then
  if profile ~= "emerald" then
    prose:override("gFameCheckerText_Cancel", "MOD_FOOTER")
  end
  if profile ~= "firered" then
    prose:override("gText_Cancel", "MOD_FOOTER")
  end
  if mode ~= "foreign" then
    prose:override("gText_WithdrawItem", "MOD_PC_TITLE")
    prose:override("gText_Withdraw", "MOD_PC_WITHDRAW")
    prose:override("gOtherText_Give", "MOD_PC_GIVE")
    -- Distinct Emerald TAKE row: it must not replace the primary TAKE.
    prose:override("gText_Take2", "OTHER_TAKE")
  end
end
if mode == "rollback" then
  error("intentional menu-prose rollback")
end
