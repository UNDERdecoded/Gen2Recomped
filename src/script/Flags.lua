-- Event flags stored in the save table, keyed by pokered event constant
-- names (e.g. "EVENT_FOLLOWED_OAK_INTO_LAB").
--
-- flag.changed fires through the runtime bus only on an actual
-- transition -- a redundant set of an already-true flag is silent -- and
-- the null bus makes the module usable headless.

local Runtime = require("src.mods.Runtime")

local Flags = {}

function Flags.set(save, name)
  local changed = save.flags[name] ~= true
  save.flags[name] = true
  if changed and Runtime.wants("flag.changed") then
    Runtime.emit("flag.changed", { name = name, value = true })
  end
end

-- Cleared flags are stored as `false`, not erased: Gen2 object_events start
-- hidden because the new-game script sets their flag, and objectVisible has to
-- tell "a script cleared this" (show the officer) from "never touched".
function Flags.clear(save, name)
  local changed = save.flags[name] == true
  save.flags[name] = false
  if changed and Runtime.wants("flag.changed") then
    Runtime.emit("flag.changed", { name = name, value = false })
  end
end

-- "Does the player have the Pokedex yet?"
--
-- Not one flag, because the cartridges do not agree on which one they set.
-- Gold and Crystal's Elm's-aide script lowers to `setevent EVENT_GOT_POKEDEX`;
-- PRISM'S PROF ILK LOWERS TO `setflag ENGINE_POKEDEX` and its own event number
-- instead, and ENGINE_POKEDEX is what the ROM's own CheckReceivedDex reads on
-- every Gen 2 cartridge.  Gating the START menu on the event alone meant the
-- Prism player watched Ilk hand the dex over -- text, jingle and all -- and
-- never got a POKeDEX entry in the menu.
function Flags.hasPokedex(save)
  -- tolerant of a save with no flag table: this is asked while menus are
  -- being built, including from headless callers
  local flags = type(save) == "table" and save.flags or nil
  if type(flags) ~= "table" then return false end
  return flags.EVENT_GOT_POKEDEX == true or flags.ENGINE_POKEDEX == true
end

function Flags.get(save, name)
  return save.flags[name] == true
end

return Flags
