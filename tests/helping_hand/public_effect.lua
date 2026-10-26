-- Composed proof: requires the canonical public effect adapter from #121.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
require("src.mods.UnifiedEffects")
for _, version in ipairs({ "firered", "emerald" }) do
  local entry = [[return function(mod)
    assert(mod.content.moves:patch("TACKLE", { effect = "HELPING_HAND", power = 0 }))
    mod.exports.effect = assert(mod.content.moves:get("TACKLE")).effect
    mod.exports.hits = {}
    mod.hooks:wrap("battle.crit", function() return false end)
    mod.hooks:wrap("battle.enemy_action", function() return { move = "SCRATCH", target = 0 } end)
    mod.events:on("battle.damage_dealt", function(e)
      mod.exports.hits[#mod.exports.hits+1] = { target = e.target.mon.nickname, amount = e.damage }
    end)
  end]]
  local function configure(data, _, ids)
    local move = data.moves[ids.TACKLE]
    move.target, move.priority, move.protectAffected = 16, 5, false
  end
  local f = require("tests.enemy_actions.fixture").new(".", "gen2", version, 3, "unified", configure, entry)
  T.eq(f.e.effect, "HELPING_HAND", "public read keeps canonical Helping Hand effect")
  T.eq(
    f.data.moves[f.ids.TACKLE].effect,
    "HELPING_HAND_EFFECT",
    "canonical effect selects real native handler"
  )
  T.eq(f.data.moves[f.ids.TACKLE].gen3Effect, 176, "canonical effect selects native semantic 176")
  local b = f.fresh("TACKLE", { enemy = true }).battle
  b.double = true
  b.rng = function(lo, hi)
    if lo == 85 and hi == 100 then
      return 100
    end
    return lo or 0
  end
  local right = require("src.battle.BattleState").makeBattler(
    f.data,
    require("src.mods.Merge").deepCopy(b.enemy.mon),
    false
  )
  b:placeBattler(3, right)
  b:syncSides()
  for _, a in ipairs({ b.player, b.enemy, right }) do
    a.curTypes, a.curStats =
      { "NORMAL" }, { hp = 400, attack = 50, defense = 50, speed = 50, special = 50, spatk = 50, spdef = 50 }
    a.mon.stats, a.abilityOverride = a.curStats, false
  end
  b.player.mon.nickname = "TARGET"
  right.curMoves = { { id = f.ids.SCRATCH, pp = 10 } }
  right.mon.moves = right.curMoves
  b:executeAction(b.enemy, b.enemy, b.enemy.curMoves[1])
  b:executeAction(right, b.player, b:enemyAction(right))
  T.same(
    f.e.hits,
    { { target = "TARGET", amount = 28 } },
    "canonical public patch boosts a real mod-selected partner attack"
  )
  T.eq(b.enemy.curMoves[1].pp, 9, "helper consumes owned PP")
  T.eq(right.curMoves[1].pp, 9, "supported action consumes caller PP")
  f.close()
end
T.finish("composed public Helping Hand effect")
