-- Shared level-display predicate for native GB/GBA screens. Only literal
-- false hides the complete level label; callers retain status/egg eligibility.
local Runtime = require("src.mods.Runtime")
local LevelDisplay = {}
local function visibleByDefault()
  return true
end

-- where: "battle.enemy" | "battle.player" | "party" | "summary"
function LevelDisplay.visible(mon, where, game)
  if not Runtime.wantsHook("pokemon.level_visible") then
    return true
  end
  return Runtime.call("pokemon.level_visible", visibleByDefault, mon, { where = where, game = game }) ~= false
end
return LevelDisplay
