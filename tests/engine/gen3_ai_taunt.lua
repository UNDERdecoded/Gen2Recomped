package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  dofile("tests/gen3_ai_taunt/cases.lua").run("gen2", version)
end
local T = require("tests.modkit")
for _, version in ipairs({ "gold", "diamond", "black" }) do
  require("src.core.GameVersion").set(version)
  local target = { name = "TARGET", isPlayer = true }
  require("src.battle.Gen3MoveEffects").primary.TAUNT_EFFECT({}, {}, target)
  T.eq(target.tauntTurns, 3, version .. " retains its existing Taunt duration")
end
T.finish("native GBA AI Taunt predicates")
