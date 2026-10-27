-- Current Gen2Recomped Gen-2 rules with finite enemy PP. This is deliberately
-- not named faithful: other differences from the reference Gold engine remain.
local out = {}
for key, value in pairs(require("src.battle.rulesets.gen1_faithful")) do
  out[key] = value
end
out.name = "gen2_finite_pp"
out.enemyUnlimitedPP = false
return out
