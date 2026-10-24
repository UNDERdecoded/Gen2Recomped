package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  dofile("tests/gen3_ai_party_status/cases.lua").run("gen2", version)
end
local T = require("tests.modkit")
local AI = require("src.battle.Gen3AI")
T.eq(AI.OPS.if_status_not_in_party, nil, "unused broken inverse is not declared supported")
for _, version in ipairs({ "red", "gold", "diamond", "black" }) do
  require("src.core.GameVersion").set(version)
  local b = { mon = {}, name = "TEST" }
  local draws = {}
  require("src.battle.Status").RECORDS.SLP.onInflict({
    rng = function(lo, hi)
      draws[#draws + 1] = { lo, hi }
      return lo
    end,
  }, b, {}, "TEST")
  T.same(draws, { { 1, 7 } }, version .. " keeps ordinary sleep RNG range")
  T.eq(b.mon.sleepTurns, nil, version .. " has no GBA party writer")
  b.mon.status, b.sleepTurns = "SLP", 1
  local ready = require("src.battle.Status").RECORDS.SLP.beforeMove(b)
  T.eq(ready, false, version .. " keeps its existing waking-turn policy")
  T.eq(b.mon.sleepTurns, nil, version .. " waking does not add GBA party state")
end
require("src.core.GameVersion").set("emerald")
do
  local actor, draws = { mon = {}, name = "TEST" }, {}
  require("src.battle.Status").RECORDS.SLP.onInflict({
    ruleset = { sleepTurnsMin = 3, sleepTurnsMax = 9 },
    rng = function(lo, hi)
      draws[#draws + 1] = { lo, hi }
      return lo
    end,
  }, actor, {}, "TEST")
  T.same(draws, { { 3, 9 } }, "explicit custom sleep range remains authoritative")
  T.eq(actor.mon.sleepTurns, 3, "custom sleep stores actual party turns")
  local battle = {
    data = { pokemon = { TEST_SPECIES = { index = 25 } } },
    enemyParty = { { species = "TEST_SPECIES", hp = 1, status = "BRN" } },
  }
  T.eq(
    require("src.battle.Gen3AIPartyStatus").matches({ battle = battle, user = { position = 1 } }, 1, 16),
    true,
    "imported species names resolve declared physical index"
  )
end
T.finish("native GBA AI party status")
