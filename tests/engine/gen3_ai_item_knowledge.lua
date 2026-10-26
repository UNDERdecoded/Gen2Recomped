package.path = "./?.lua;./?/init.lua;" .. package.path
for _, version in ipairs({ "firered", "emerald" }) do
  dofile("tests/gen3_ai_item_knowledge/cases.lua").run("gen2", version)
end
local T = require("tests.modkit")
for _, version in ipairs({ "red", "gold", "diamond", "black" }) do
  require("src.core.GameVersion").set(version)
  local draws = {}
  local actor = { name = "TEST", isPlayer = true, mon = {}, confusedTurns = 3 }
  local battle = { data = { constants = { generation = require("src.core.GameVersion").generation() } } }
  local canMove, _, selfHit = require("src.battle.Status").beforeMove(actor, function(lo, hi)
    draws[#draws + 1] = { lo, hi }
    return 0
  end, battle)
  T.eq(canMove, false, version .. " keeps its existing confusion decision")
  T.eq(selfHit, true, version .. " keeps its existing self-hit decision")
  T.same(draws, { { 0, 255 } }, version .. " keeps byte-range confusion RNG")
  local proto = { data = {} }
  setmetatable(proto, { __index = require("src.battle.BattleState") })
  local vanilla = require("src.battle.MoveEffects").RECORDS.OHKO_EFFECT
  T.eq(proto:effectRecord("OHKO_EFFECT"), vanilla, version .. " keeps its existing OHKO policy")
end
require("src.core.GameVersion").set("emerald")
do
  local vanilla = require("src.battle.MoveEffects").RECORDS.OHKO_EFFECT
  local custom = {}
  for k, v in pairs(vanilla) do
    custom[k] = v
  end
  custom.gate = function()
    return false, "custom"
  end
  local proto = setmetatable(
    { data = { move_effects = { OHKO_EFFECT = custom } } },
    { __index = require("src.battle.BattleState") }
  )
  T.eq(proto:effectRecord("OHKO_EFFECT"), custom, "explicit mod OHKO gate is not replaced")
end
require("tests.modkit").finish("native GBA AI item knowledge")
