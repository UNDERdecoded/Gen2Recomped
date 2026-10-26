-- Regression from actual FireRed/Emerald opponent-controller comparisons:
-- base damage 11, critical x2, Steel resistance and roll 85 gives 9, not 8.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Damage, TypeChart = require("src.battle.Damage"), require("src.battle.TypeChart")
local copy = require("src.mods.Merge").deepCopy
local rules = require("src.battle.rulesets.gen3_emerald")
TypeChart.load({
  type_chart = {
    types = {},
    matchups = {
      { attacker = "NORMAL", defender = "STEEL", multiplier = 5 },
      { attacker = "NORMAL", defender = "RESIST", multiplier = 5 },
      { attacker = "NORMAL", defender = "WEAK", multiplier = 20 },
      { attacker = "NORMAL", defender = "GHOST", multiplier = 0 },
    },
  },
})
local function battler(types)
  return {
    mon = { level = 30, hp = 400 },
    def = {},
    stages = {},
    curTypes = types,
    curStats = { hp = 400, attack = 50, defense = 50, special = 50, spatk = 50, spdef = 50 },
  }
end
local move = { id = "TACKLE", type = "NORMAL", power = 35 }
-- Literal expectations guard resistance, authored super-effectiveness,
-- STAB, immunity and adjacent noncritical boundaries. The Steel regression
-- is also reproduced through both actual native opponent controllers.
for _, row in ipairs({
  { false, false, { "STEEL" }, 85, 4 },
  { true, false, { "STEEL" }, 85, 9 },
  { true, false, { "STEEL" }, 100, 11 },
  { true, false, { "STEEL", "RESIST" }, 85, 4 },
  { true, false, { "STEEL", "RESIST" }, 100, 5 },
  { true, false, { "NEUTRAL" }, 85, 18 },
  { true, false, { "NEUTRAL" }, 100, 22 },
  { true, false, { "WEAK" }, 85, 37 },
  { true, true, { "STEEL" }, 85, 13 },
  { true, true, { "STEEL", "RESIST" }, 85, 6 },
  { true, true, { "NEUTRAL" }, 85, 28 },
  { true, false, { "GHOST" }, 85, 0 },
}) do
  local value = Damage.compute(rules, battler({ row[2] and "NORMAL" or "OTHER" }), battler(row[3]), move, {
    forceCrit = row[1],
    rng = function()
      return row[4]
    end,
  })
  T.eq(value, row[5], "native critical/type rounding " .. table.concat(row[3], "/") .. " roll " .. row[4])
end
local legacy = copy(rules)
legacy.critBeforeType = nil
T.eq(
  Damage.compute(legacy, battler({ "OTHER" }), battler({ "STEEL" }), move, {
    forceCrit = true,
    rng = function()
      return 85
    end,
  }),
  8,
  "profiles without the flag retain their ordering"
)
T.eq(require("src.battle.rulesets.gen4_platinum").critBeforeType, nil, "Gen-4 profile is not changed")
T.eq(require("src.battle.rulesets.gen1_faithful").critBeforeType, nil, "Gen-1 profile is not changed")
T.finish("Gen-3 critical/type ordering")
