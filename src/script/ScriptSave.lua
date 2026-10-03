-- ONE SAVE WRITE FOR EVERY GENERATION'S SCRIPT SAVE COMMAND.
--
-- Gen 3's `special SaveGame` (96) and Gen 4's `trysavegame` (0x12D) ask the
-- engine the same question -- "write the save, and tell me whether it
-- happened" -- and before this they would have asked it in two different
-- files.  That is the shape of the bug this port keeps finding: the same thing
-- spelled twice in two places that never meet, so a fix to one leaves the
-- other wrong.  Gen 3's sentence was already written and correct, so it moved
-- here verbatim rather than being rewritten, and Gen 4 reads the same one.
--
-- THE WRITE IS THE ENGINE'S OWN, not a second save path.  `Game:writeSave`
-- captures the overworld into the save the way F1 and the START menu do, gives
-- a tool session its veto (the `save.write` mod hook), and lets mods snapshot
-- into their namespace on the way past.  A veto, a failed write or a raise
-- answers false, which is the arm every cartridge's script already has for
-- "it did not happen": Hoenn's tent attendant says nothing more and lets you
-- walk away, and Sinnoh's save script prints `Save error.`
local Logger = require("src.core.Logger")

local ScriptSave = {}

-- true when the bytes reached disk, false otherwise.  `who` only names the
-- caller in the log line, so the two generations stay distinguishable in a
-- player's log without being distinguishable in behaviour.
function ScriptSave.write(ctx, who)
  who = who or "script"
  local game = ctx and ctx.game
  if game and game.writeSave then
    local ok, result = pcall(game.writeSave, game)
    if not ok then
      Logger.warn("%s save: the script's save failed: %s", who, tostring(result))
      return false
    end
    return result ~= false
  end
  -- headless: no Game to capture through, so the save table is written as
  -- it stands.  The scripts still need their answer.
  if ctx and ctx.save then
    local okReq, SaveData = pcall(require, "src.core.SaveData")
    if okReq and SaveData and SaveData.save then
      return pcall(SaveData.save, ctx.save) and true or false
    end
  end
  return false
end

return ScriptSave
