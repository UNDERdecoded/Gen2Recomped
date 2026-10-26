-- Native GBA weather suppression observes every occupied battle slot.
local M = {}
function M.effective(battle)
  local sky = require("src.battle.Weather").raw(battle)
  if not sky then
    return nil
  end
  local Abilities = require("src.battle.Abilities")
  for _, b in battle:activeBattlers() do
    local ability = Abilities.of(b)
    if ability == "CLOUD_NINE" or ability == "AIR_LOCK" then
      return nil
    end
  end
  return sky == "SANDSTORM" and "SAND" or sky
end
return M
