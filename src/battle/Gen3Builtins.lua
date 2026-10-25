-- Adapt complete builtin records before mods capture them for delegation.
local M = {}
function M.record(id, base)
  if id == "ASSIST_EFFECT" and require("src.core.GameVersion").isGen3() then
    return base or require("src.battle.Gen3Assist").record()
  end
  if id == "NATURE_POWER_EFFECT" and require("src.core.GameVersion").isGen3() then
    return base or require("src.battle.Gen3NaturePower").record()
  end
  base = require("src.battle.Gen3Disable").builtin(id, base)
  base = require("src.battle.Gen3MultiHit").builtin(id, base)
  base = require("src.battle.Gen3Rage").builtin(id, base)
  base = require("src.battle.Gen3TripleKick").builtin(id, base)
  base = require("src.battle.Gen3ChoiceBand").builtin(id, base)
  return require("src.battle.Gen3SleepTalk").builtin(id, base)
end
function M.install(registry, owner)
  if require("src.core.GameVersion").isGen3() then
    registry:register("NATURE_POWER_EFFECT", require("src.battle.Gen3NaturePower").record(), owner)
    registry:register("ASSIST_EFFECT", require("src.battle.Gen3Assist").record(), owner)
  end
end
return M
