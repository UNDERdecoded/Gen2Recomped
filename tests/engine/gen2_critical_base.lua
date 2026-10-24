-- Found by ordinary Gen-2 turns in the cross-engine decision contracts.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Damage = require("src.battle.Damage")
require("src.battle.TypeChart").load({ type_chart = { types = {}, matchups = {} } })
local rules = require("src.battle.rulesets.gen1_faithful")
local function mon(level, types)
  return {
    mon = { level = level, hp = 400 },
    def = {},
    stages = {},
    curTypes = types,
    curStats = { hp = 400, attack = 50, defense = 50, special = 50 },
  }
end
local move = { id = "TACKLE", type = "NORMAL", power = 35 }
for _, row in ipairs({
  { 29, true, false, 17 },
  { 29, true, true, 25 },
  { 29, false, false, 9 },
  { 1, true, false, 3 },
  { 3, true, false, 5 },
  { 30, true, false, 17 },
}) do
  local got =
    Damage.compute(rules, mon(row[1], { row[3] and "NORMAL" or "OTHER" }), mon(30, { "OTHER" }), move, {
      forceCrit = row[2],
      data = { constants = { generation = 2 } },
      rng = function()
        return 217
      end,
    })
  T.eq(got, row[4], "Gen-2 native critical base level " .. row[1])
end
T.eq(
  Damage.compute(rules, mon(29, { "OTHER" }), mon(30, { "OTHER" }), move, {
    forceCrit = true,
    rng = function()
      return 217
    end,
  }),
  16,
  "Gen-1 still doubles the level"
)
T.finish("Gen-2 critical base")
