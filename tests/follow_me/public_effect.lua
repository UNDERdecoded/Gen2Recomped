-- Composed proof: requires the canonical effect adapter from PR #121.
-- Run explicitly after integrating both PRs; it must fail without either one.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
require("src.mods.UnifiedEffects")
for _, version in ipairs({ "firered", "emerald" }) do
  local entry = [[return function(mod)
    assert(mod.content.moves:patch("TACKLE", {
      effect = "FOLLOW_ME", power = 0
    }))
    mod.exports.effect = assert(mod.content.moves:get("TACKLE")).effect
    mod.exports.hits = {}
    mod.hooks:wrap("battle.enemy_action", function()
      return { move = "SCRATCH", target = 2 }
    end)
    mod.events:on("battle.damage_dealt", function(e)
      mod.exports.hits[#mod.exports.hits + 1] = e.target.mon.nickname
    end)
  end]]
  local function configure(data, _, ids)
    local move = data.moves[ids.TACKLE]
    move.target, move.priority, move.protectAffected = 16, 3, false
  end
  local f = require("tests.enemy_actions.fixture").new(".", "gen2", version, 3, "unified", configure, entry)
  local e = f.e
  T.eq(#f.result.errors, 0, version .. " real API-3 effect mod loads")
  T.eq(e.effect, "FOLLOW_ME", "public canonical read matches authored effect")
  T.eq(f.data.moves[f.ids.TACKLE].effect, "FOLLOW_ME_EFFECT", "canonical patch selects real native handler")
  T.eq(f.data.moves[f.ids.TACKLE].gen3Effect, 172, "canonical patch preserves native semantic number")
  local b = f.fresh("TACKLE", { enemy = true }).battle
  b.double = true
  local right = require("src.battle.BattleState").makeBattler(
    f.data,
    require("src.mods.Merge").deepCopy(b.player.mon),
    true
  )
  b:placeBattler(2, right)
  b:syncSides()
  b.player.mon.nickname, right.mon.nickname = "CENTER", "ORIGINAL"
  b.player.curMoves = { { id = f.ids.TACKLE, pp = 10 } }
  b.enemy.curMoves = { { id = f.ids.SCRATCH, pp = 10 } }
  b.player.mon.moves, b.enemy.mon.moves = b.player.curMoves, b.enemy.curMoves
  b:executeAction(b.player, b.player, b.player.curMoves[1])
  b:executeAction(b.enemy, right, b:enemyAction(b.enemy))
  T.same(e.hits, { "CENTER" }, "public effect patch redirects a real mod-selected native attack")
  T.eq(b.player.curMoves[1].pp, 9, "canonical producer spends owned PP")
  T.eq(b.enemy.curMoves[1].pp, 9, "redirected action spends caller PP")
  f.close()
end
T.finish("composed public Follow Me effect")
