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

function Flags.get(save, name)
  return save.flags[name] == true
end

return Flags
