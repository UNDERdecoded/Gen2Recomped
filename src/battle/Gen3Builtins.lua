-- Adapt complete builtin records before mods capture them for delegation.
local M = {}
function M.record(id, base)
  base = require("src.battle.Gen3Disable").builtin(id, base)
  base = require("src.battle.Gen3MultiHit").builtin(id, base)
  base = require("src.battle.Gen3Rage").builtin(id, base)
  base = require("src.battle.Gen3TripleKick").builtin(id, base)
  return require("src.battle.Gen3SleepTalk").builtin(id, base)
end
return M
