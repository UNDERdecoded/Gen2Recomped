package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  dofile("tests/gba_damage_base/cases.lua").run("gen2", version)
end
-- Profiles without the GBA opt-in retain their existing arithmetic.
local T = require("tests.modkit")
local D = require("src.battle.Damage")
local rules = require("src.battle.rulesets.gen1_faithful")
for _, generation in ipairs({ 1, 2 }) do
  local data = {
    constants = { generation = generation },
    items = {},
    type_chart = { types = { NORMAL = { category = "physical" } }, matchups = {} },
  }
  require("src.battle.TypeChart").load(data)
  local function oldDamage(level, power, attack, defense)
    return D.compute(
      rules,
      { mon = { level = level, hp = 400 }, curStats = { attack = attack }, curTypes = { "NORMAL" } },
      { mon = { hp = 400 }, curStats = { defense = defense }, curTypes = { "NORMAL" } },
      { id = "BASE_RETENTION", power = power, type = "NORMAL" },
      {
        forceCrit = false,
        data = data,
        rng = function()
          return 255
        end,
      }
    )
  end
  T.eq(oldDamage(1, 2, 50, 50), 3, "older minimum-base arithmetic retained")
  T.eq(oldDamage(30, 35, 300, 50), 94, "older paired stat scaling retained")
  T.eq(oldDamage(30, 250, 500, 10), 1498, "older base damage cap retained")
end
T.finish("ordinary GBA base damage and older-profile retention")
