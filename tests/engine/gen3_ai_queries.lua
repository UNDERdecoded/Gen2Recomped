package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  dofile("tests/gen3_ai_queries/cases.lua").run("gen2", version)
end
local T, AI = require("tests.modkit"), require("src.battle.Gen3AI")
local program = {
  entries = { [0] = 1 },
  code = {
    { name = "if_equal", args = { 0, 3 }, next = 2 },
    { name = "end", args = {} },
    { name = "UNSUPPORTED_AI_QUERY", args = {}, next = 4 },
    { name = "end", args = {} },
  },
}
T.eq(AI.runs(program, 1), false, "unsupported reachable queries still reject the whole script")
local draws = 0
local battle = {
  trainer = { aiFlags = 1 },
  rng = function()
    draws = draws + 1
    return 0
  end,
  data = { constants = { gen3BattleAI = program }, moves = { TEST = { index = 33 } } },
}
T.eq(
  AI.scoreMoves(battle, {}, {}, { { id = "TEST", pp = 10 } }),
  nil,
  "unsupported scripts cannot supply partial scores"
)
T.eq(draws, 0, "skipped unsupported scripts cannot consume RNG")
T.finish("native GBA AI move and battler queries")
